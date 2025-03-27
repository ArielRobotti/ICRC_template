///This is a naieve token implementation and shows the minimum possible implementation. It does not provide archiving and will not scale.
///Please see https://github.com/PanIndustrial-Org/ICRC_fungible for a full featured implementation

import ExperimentalCycles "mo:base/ExperimentalCycles";
import Principal "mo:base/Principal";
import Map "mo:map/Map";
import { ihash } "mo:map/Map";
import { now } "mo:base/Time";
import Nat64 "mo:base/Nat64";
import Int "mo:base/Int";
import Array "mo:base/Array";


import ICRC1 "mo:icrc1-mo/ICRC1";
import ICRC2 "mo:icrc2-mo/ICRC2";
import Types "types"

shared ({ caller = _owner }) actor class Token(
    init_args1 : ICRC1.InitArgs,
    init_args2 : ICRC2.InitArgs,
    initial_distribution : ?Types.InitialDsitribution,
) = this {

    let icrc1_args : ICRC1.InitArgs = {
        init_args1 with minting_account = switch (
            init_args1.minting_account
        ) {
            case (?val) ?val;
            case (null) {
                ?{
                    owner = _owner;
                    subaccount = null;
                };
            };
        };
    };

    let icrc2_args : ICRC2.InitArgs = init_args2;

    stable let icrc1_migration_state = ICRC1.init(ICRC1.initialState(), #v0_1_0(#id), ?icrc1_args, _owner);

    let #v0_1_0(#data(icrc1_state_current)) = icrc1_migration_state;

    private var _icrc1 : ?ICRC1.ICRC1 = null;

    private func get_icrc1_state() : ICRC1.CurrentState {
        return icrc1_state_current;
    };

    private func get_icrc1_environment() : ICRC1.Environment {
        {
            get_time = null;
            get_fee = null;
            add_ledger_transaction = null;
            can_transfer = null;
        };
    };

    func icrc1() : ICRC1.ICRC1 {
        switch (_icrc1) {
            case (null) {
                let initclass : ICRC1.ICRC1 = ICRC1.ICRC1(?icrc1_migration_state, Principal.fromActor(this), get_icrc1_environment());
                _icrc1 := ?initclass;
                initclass;
            };
            case (?val) val;
        };
    };

    stable let icrc2_migration_state = ICRC2.init(ICRC2.initialState(), #v0_1_0(#id), ?icrc2_args, _owner);

    let #v0_1_0(#data(icrc2_state_current)) = icrc2_migration_state;

    private var _icrc2 : ?ICRC2.ICRC2 = null;

    private func get_icrc2_state() : ICRC2.CurrentState {
        return icrc2_state_current;
    };

    private func get_icrc2_environment() : ICRC2.Environment {
        {
            icrc1 = icrc1();
            get_fee = null;
            can_approve = null;
            can_transfer_from = null;
        };
    };

    func icrc2() : ICRC2.ICRC2 {
        switch (_icrc2) {
            case (null) {
                let initclass : ICRC2.ICRC2 = ICRC2.ICRC2(?icrc2_migration_state, Principal.fromActor(this), get_icrc2_environment());
                _icrc2 := ?initclass;
                initclass;
            };
            case (?val) val;
        };
    };

    ////// Initial Distribution 

    type LockedAmount = {
        unlockDate: Int;
        amount: Nat;
    };

    stable var distributedAmount  = 0;
    stable var distribution_is_ended = false;
    stable let holders_unlock_dates = Map.new<Types.Account, LockedAmount>(); // Account/Timestamp de desbloqueo de tokens de distribucion


    func _distribution(): async {#Ok; #Err: Text} {
        if(distribution_is_ended) { return #Err("Distribution is ended") };

        switch initial_distribution {
            case null { return #Err("There is no initial distribution") }; 
            case ( ?dist ) {
                for(category in dist.categories.vals()) {
                    for (holder in category.holders.vals()) {
                        let mint_args: ICRC1.Mint = {
                            to = holder;
                            created_at_time = ? Nat64.fromNat(Int.abs(now()));
                            amount = category.allocatedAmount;
                            memo = null;
                        };
                        let _mint_result = await* icrc1().mint(icrc1().minting_account().owner, mint_args);
                        switch _mint_result {
                            case (#Err(_)) { };
                            case (#Ok(_)) {
                                distributedAmount += category.allocatedAmount;
                                let unlock_date = now() + category.blockingDays * 5 * 1_000_000_000; //24 * 60 * 60 * 1_000_000_000; //    Cantidad de dias expresada en nanosegundos
                                let locked_ammount: LockedAmount = { unlockDate = unlock_date; amount = category.allocatedAmount };
                                ignore Map.put<Types.Account, LockedAmount>(holders_unlock_dates, ICRC1.ahash, holder, locked_ammount);
                            };
                        };
                    }
                }
            };
        };

        distribution_is_ended := true;
        #Ok
    };
    
    type DistributionInfo = {
        amountCurrentlyBlocked: Nat;
        amountReleasedToDate: Nat;
        releases: [{date: Int; amount: Nat}];
    };

    func getDistributionStatus(): ?DistributionInfo {
        let releasesMap = Map.new<Int, Nat>(); // Fecha de desbloqueo / Monto a desbloquear
        let currentTime = now();
        var amountCurrentlyBlocked = 0;
        for (holder in Map.vals(holders_unlock_dates)) {
            if (currentTime < holder.unlockDate) { 
                amountCurrentlyBlocked += holder.amount 
            };
            switch (Map.remove<Int, Nat>(releasesMap, ihash, holder.unlockDate)) {
                case null {
                    
                    ignore Map.put<Int, Nat>(releasesMap, ihash, holder.unlockDate, holder.amount) 
                };
                case ( ?val ) { 
                    ignore Map.put<Int, Nat>(releasesMap, ihash, holder.unlockDate, val + holder.amount) 
                };
            };
        };

        let amountReleasedToDate: Nat = distributedAmount - amountCurrentlyBlocked;

        let entries = Map.toArray(releasesMap);

        let releases = Array.map<(Int, Nat), {date: Int; amount: Nat}>(
            entries,
            func x = { date = x.0; amount = x.1 }
        );
        ? {amountCurrentlyBlocked; amountReleasedToDate; releases}

    };

    public shared ({ caller }) func distribution_info(): async ?DistributionInfo {
        if(not distribution_is_ended and caller == _owner) { 
            ignore await _distribution();
            return getDistributionStatus() 
        };
        getDistributionStatus();
    };

    func validate_transaction({from: Principal; amount: Nat; from_subaccount: ?Blob}): Bool {
        let currentTime = now();
        let fromAccount = {owner = from; subaccount = from_subaccount};

        let lockedAmount = Map.get<Types.Account, LockedAmount>(holders_unlock_dates, ICRC1.ahash, fromAccount);
        switch lockedAmount {
            case null {return true};
            case ( ?lockedAmount) {
                if (currentTime < lockedAmount.unlockDate) {
                    let balance = icrc1().balance_of(fromAccount);
                    return (balance - amount - icrc1().fee()): Nat >= lockedAmount.amount;
                };
                return true;
            }
        }
    };

    // func transfer_with_validation(caller: Principal, args : ICRC1.TransferArgs): async ICRC1.TransferResult {

    // };

    /// Functions for the ICRC1 token standard
    public shared query func icrc1_name() : async Text {
        icrc1().name();
    };

    public shared query func icrc1_symbol() : async Text {
        icrc1().symbol();
    };

    public shared query func icrc1_decimals() : async Nat8 {
        icrc1().decimals();
    };

    public shared query func icrc1_fee() : async ICRC1.Balance {
        icrc1().fee();
    };

    public shared query func icrc1_metadata() : async [ICRC1.MetaDatum] {
        icrc1().metadata();
    };

    public shared query func icrc1_total_supply() : async ICRC1.Balance {
        icrc1().total_supply();
    };

    public shared query func icrc1_minting_account() : async ?ICRC1.Account {
        ?icrc1().minting_account();
    };

    public shared query func icrc1_balance_of(args : ICRC1.Account) : async ICRC1.Balance {
        icrc1().balance_of(args);
    };

    public shared query func icrc1_supported_standards() : async [ICRC1.SupportedStandard] {
        icrc1().supported_standards();
    };

    public shared ({ caller }) func icrc1_transfer(args : ICRC1.TransferArgs) : async ICRC1.TransferResult {
        if(not validate_transaction({args with from = caller})) { return #Err(#GenericError( {error_code = 1; message = "Insufficient unblocked funds"}))};
        await* icrc1().transfer(caller, args);
    };

    public shared ({ caller }) func mint(args : ICRC1.Mint) : async ICRC1.TransferResult {
        await* icrc1().mint(caller, args);
    };

    public shared ({ caller }) func burn(args : ICRC1.BurnArgs) : async ICRC1.TransferResult {
        await* icrc1().burn(caller, args);
    };

    public query ({ caller }) func icrc2_allowance(args : ICRC2.AllowanceArgs) : async ICRC2.Allowance {
        return icrc2().allowance(args.spender, args.account, false);
    };

    public shared ({ caller }) func icrc2_approve(args : ICRC2.ApproveArgs) : async ICRC2.ApproveResponse {
        if(not validate_transaction({args with from = caller})) { return #Err(#GenericError( {error_code = 1; message = "Insufficient unblocked funds"}))};
        await* icrc2().approve(caller, args);
    };

    public shared ({ caller }) func icrc2_transfer_from(args : ICRC2.TransferFromArgs) : async ICRC2.TransferFromResponse {
        let trxValid = validate_transaction({
            from = args.from.owner;
            from_subaccount = args.from.subaccount;
            amount = args.amount;
        });
        if(not trxValid) { return #Err(#GenericError( {error_code = 1; message = "Insufficient unblocked funds"})) };
        await* icrc2().transfer_from(caller, args);
    };

    // Deposit cycles into this canister.
    public shared func deposit_cycles() : async () {
        let amount = ExperimentalCycles.available();
        let accepted = ExperimentalCycles.accept<system>(amount);
        assert (accepted == amount);
    };
};
