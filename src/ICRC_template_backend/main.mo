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
import Nat "mo:base/Nat";

import ICRC1 "mo:icrc1-mo/ICRC1";
import ICRC2 "mo:icrc2-mo/ICRC2";
import Types "types";
import { print } "mo:base/Debug";

shared ({ caller = _owner }) actor class Token({
    icrc1_init_args : ICRC1.InitArgs;
    icrc2_init_args : ICRC2.InitArgs;
    initial_distribution : [Types.HolderCategory];
    fee_distribution_percentages: {toBurn : Nat; pooles: [Types.FeeAllocationPercentages]}; //Multiplicar por 100. Ej: para expresar un 2.25 por ciento poner 225
}) = this {

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
        icrc1().fee() + fee_distribution_percentages.toBurn;    
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
        switch (validate_transaction({ args with from = caller })) {
            case (#Ok) {
                let trxResult = await* icrc1().transfer(caller, args);
                switch trxResult {
                    case (#Ok(_)) {
                        print(debug_show (await* icrc1().burn( caller, {args with  amount = fee_distribution_percentages.toBurn })));
                    };
                    case _ {}
                };
                trxResult
                
            };
            case (#Err(err)) { #Err(err) };
        };
    };

    public shared ({ caller }) func mint(args : ICRC1.Mint) : async ICRC1.TransferResult {
        await* icrc1().mint(caller, args);
    };

    public shared ({ caller }) func burn(args : ICRC1.BurnArgs) : async ICRC1.TransferResult {
        await* icrc1().burn(caller, args);
    };

    /// Functions for the ICRC2 token standard
    public query ({ caller }) func icrc2_allowance(args : ICRC2.AllowanceArgs) : async ICRC2.Allowance {
        return icrc2().allowance(args.spender, args.account, false);
    };

    public shared ({ caller }) func icrc2_approve(args : ICRC2.ApproveArgs) : async ICRC2.ApproveResponse {

        switch (validate_transaction({ args with from = caller })) {
            case (#Ok) {
                await* icrc2().approve(caller, args);
            };
            case (#Err(err)) {
                switch (err) {
                    case (#InsufficientFunds(data)) {
                        #Err(#InsufficientFunds(data));
                    };
                    case (#GenericError(genError)) {
                        #Err(#GenericError(genError));
                    };
                    case (_) {
                        #Err(#GenericError({ error_code = 0; message = "Unsepected Error" }));
                    };
                };
            };
        };
    };

    public shared ({ caller }) func icrc2_transfer_from(args : ICRC2.TransferFromArgs) : async ICRC2.TransferFromResponse {
        let check_transaction = validate_transaction({
            from = args.from.owner;
            from_subaccount = args.from.subaccount;
            amount = args.amount;
        });
        switch check_transaction {
            case (#Ok) {
                let trxResult = await* icrc2().transfer_from(caller, args);
                switch trxResult {
                    case (#Ok(_)){
                        ignore await* icrc1().burn( 
                            args.from.owner, 
                            {   args with  
                                amount = fee_distribution_percentages.toBurn;
                                from_subaccount = args.from.subaccount
                            });    
                    };
                    case (_) {}
                };
                trxResult
            };
            case (#Err(err)) { #Err(err) };
        };
    };

    // Deposit cycles into this canister.
    public shared func deposit_cycles() : async () {
        let amount = ExperimentalCycles.available();
        let accepted = ExperimentalCycles.accept<system>(amount);
        assert (accepted == amount);
    };

    // Distribution custom functions

    public shared ({ caller }) func distribution_info() : async ?DistributionInfo {
        if (not distribution_is_started and caller == _owner) {
            await _distribution();
        };
        getDistributionStatus();
    };

    /////////////////// Initialization token state //////////////////////////////////

    let icrc1_args : ICRC1.InitArgs = {
        icrc1_init_args with minting_account = switch ( icrc1_init_args.minting_account ) {
            case (?val) ?val;
            case (null) {
                ?{ owner = _owner; subaccount = null };
            };
        };
        fee = switch (icrc1_init_args.fee){
            case ( ? #Fixed(_fee) ) { ? #Fixed(_fee: Nat - (fee_distribution_percentages.toBurn * _fee) /10000: Nat)};
            case ( _ ) {  ? #Fixed(10_000: Nat - fee_distribution_percentages.toBurn: Nat) }
        };
    };

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

    stable let icrc2_migration_state = ICRC2.init(ICRC2.initialState(), #v0_1_0(#id), ?icrc2_init_args, _owner);

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

    ///////////////////////// Distribution section ///////////////////////////
    // Para iniciar la distribución, si es que fue configurada en el deploy, el owner debe llamar a la función publica
    // distribution_info la cual ejecutará la distribución de tokens por unica vez y retornará la información de la distribución.
    // Si la llamada la efectua un usuario distinto al owner, la función solo retornará la información actual de la distribución
    // sin ejecutar la distribución de tokens, independientemente de si la distribución ya fue efectuada por el owner o no.

    type LockedAmount = {
        unlockDate : Int; // Timestamp de desbloqueo de tokens de distribucion
        amount : Nat; // Monto de tokens bloqueados
    };

    stable var distributedAmount = 0;
    stable var distribution_is_started = false;
    stable let holders_unlock_dates = Map.new<Types.Account, LockedAmount>();

    func _distribution() : async () {
        if (distribution_is_started) { return }; // Es redundante si solo se llama desde la funcion publica distribution_info
        distribution_is_started := true;

        if (initial_distribution.size() == 0 ) {return };

        for (category in initial_distribution.vals()) {
            for (holder in category.holders.vals()) {
                let mint_args : ICRC1.Mint = {
                    to = holder;
                    created_at_time = ?Nat64.fromNat(Int.abs(now()));
                    amount = category.allocatedAmount;
                    memo = null;
                };
                let _mint_result = await* icrc1().mint(icrc1().minting_account().owner, mint_args);
                switch _mint_result {
                    case (#Err(_)) {};
                    case (#Ok(_)) {
                        distributedAmount += category.allocatedAmount;
                        let unlock_date = now() + category.blockingDays * 24 * 60 * 60 * 1_000_000_000; //5 * 1_000_000_000; //  Nanosegundos por dia
                        let locked_ammount : LockedAmount = {
                            unlockDate = unlock_date;
                            amount = category.allocatedAmount;
                        };
                        ignore Map.put<Types.Account, LockedAmount>(holders_unlock_dates, ICRC1.ahash, holder, locked_ammount);
                    };
                };
            };
        };
    };

    type DistributionInfo = {
        amountCurrentlyBlocked : Nat;
        amountReleasedToDate : Nat;
        releases : [{ date : Int; amount : Nat }];
    };

    func getDistributionStatus() : ?DistributionInfo {
        let releasesMap = Map.new<Int, Nat>(); // Fecha de desbloqueo / Monto a desbloquear
        let currentTime = now();
        var amountCurrentlyBlocked = 0;
        for (holder in Map.vals(holders_unlock_dates)) {
            if (currentTime < holder.unlockDate) {
                amountCurrentlyBlocked += holder.amount;
            };
            switch (Map.remove<Int, Nat>(releasesMap, ihash, holder.unlockDate)) {
                case null {
                    ignore Map.put<Int, Nat>(releasesMap, ihash, holder.unlockDate, holder.amount);
                };
                case (?val) {
                    ignore Map.put<Int, Nat>(releasesMap, ihash, holder.unlockDate, val + holder.amount);
                };
            };
        };
        let amountReleasedToDate : Nat = distributedAmount - amountCurrentlyBlocked;

        let entries = Map.toArray(releasesMap);

        let releases = Array.map<(Int, Nat), { date : Int; amount : Nat }>(
            entries,
            func x = { date = x.0; amount = x.1 },
        );
        ?{ amountCurrentlyBlocked; amountReleasedToDate; releases }

    };

    func validate_transaction({ from: Principal; amount: Nat; from_subaccount: ?Blob }): { #Ok; #Err: ICRC1.TransferError } {
        let currentTime = now();
        let fromAccount = { owner = from; subaccount = from_subaccount };

        let lockedAmount = Map.get<Types.Account, LockedAmount>(holders_unlock_dates, ICRC1.ahash, fromAccount);
        switch lockedAmount {
            case null { return #Ok };
            case (?lockedAmount) {
                if (currentTime < lockedAmount.unlockDate) {
                    let balance = icrc1().balance_of(fromAccount);
                    if (balance < amount + icrc1().fee()) {
                        return #Err(#InsufficientFunds({ balance = balance }));
                    };
                    return switch ((balance - amount - icrc1().fee()) : Nat >= lockedAmount.amount) {
                        case (true) { #Ok };
                        case (false) {
                            #Err(#GenericError({ error_code = 18; message = "Insufficient unlocked balance" }));
                        };
                    };
                };
                return #Ok;
            };
        };
    };

};
