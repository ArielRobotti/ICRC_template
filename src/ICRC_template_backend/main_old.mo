import Types "types";
import ICRC1 "mo:icrc1-mo/ICRC1";
import ICRC2 "mo:icrc2-mo/ICRC2";
import Principal "mo:base/Principal";
shared ({ caller = _owner }) actor class (init_args : ICRC1.InitArgs) = this {

    stable let init_args1: ICRC1.InitArgs = init_args;
    // stable let init_args2: ICRC2.InitArgs = init_args;

    let icrc1_args1 : ICRC1.InitArgs = {
        init_args with minting_account = switch (
            init_args.minting_account
        ) {
            case (?val) ?val;
            case (null) { ?{ owner = _owner; subaccount = null } };
        };
    };
    
    stable let icrc1_migration_state = ICRC1.init(ICRC1.initialState(), #v0_1_0(#id), ?init_args, _owner);
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

    // stable let icrc2_migration_state = ICRC2.init(ICRC2.initialState(), #v0_1_0(#id), ?icrc2_args, _owner);

    // let #v0_1_0(#data(icrc2_state_current)) = icrc2_migration_state;

    private var _icrc2 : ?ICRC2.ICRC2 = null;

    // private func get_icrc2_state() : ICRC2.CurrentState {
    //     return icrc2_state_current;
    // };

    // private func get_icrc2_environment() : ICRC2.Environment {
    //     {
    //         icrc1 = icrc1();
    //         get_fee = null;
    //         can_approve = null;
    //         can_transfer_from = null;
    //     };
    // };

    // func icrc2() : ICRC2.ICRC2 {
    //     switch (_icrc2) {
    //         case (null) {
    //             let initclass : ICRC2.ICRC2 = ICRC2.ICRC2(?icrc2_migration_state, Principal.fromActor(this), get_icrc2_environment());
    //             _icrc2 := ?initclass;
    //             initclass;
    //         };
    //         case (?val) val;
    //     };
    // };
};
