import Blob "mo:base/Blob";
import Principal "mo:base/Principal";
// import ICRC1 "mo:icrc1-mo/ICRC1";

module {

    public type Account = { owner : Principal; subaccount : ?Blob };

    public type HolderCategory = {
        name: Text;         // Nombre de la categoría eg: founders, team, testers, etc
        holders: [Account];
        allocatedAmount : Nat;
        blockingDays: Nat   // Periodo de bloqueo luego de la distribución inicial
    };

    public type InitialDsitribution = {
        categories: [HolderCategory];    
    };

    public type FeeAllocationPercentages = {
        name: Text;
        account: Account;
        percent: Nat
    };

    public func checkFeeAllocationPercentages(allocationsFee: [FeeAllocationPercentages]): Bool {
        var accumulator = 0;
        for(a in allocationsFee.vals()) {
            accumulator += a.percent;
        };
        return accumulator <= 100 * 100
    };


}