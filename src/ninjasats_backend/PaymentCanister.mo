// ============================================
// FILE: src/canisters/PaymentCanister.mo
// Handles satoshi payments, escrow, and transactions
// ============================================

import Principal "mo:base/Principal";
import HashMap "mo:base/HashMap";
import Hash "mo:base/Hash";
import Iter "mo:base/Iter";
import Time "mo:base/Time";
import Nat "mo:base/Nat";
import Result "mo:base/Result";
import Array "mo:base/Array";
import Buffer "mo:base/Buffer";
import Order "mo:base/Order";
import Option "mo:base/Option";

actor PaymentCanister {
  
  type UserId = Principal;
  type TaskId = Nat;
  type TransactionId = Nat;
  
  public type TransactionType = {
    #Deposit;
    #Withdrawal;
    #TaskPayment;
    #Refund;
    #Bonus;
    #Fee;
    #EscrowLock;
    #EscrowRelease;
  };
  
  public type TransactionStatus = {
    #Pending;
    #Completed;
    #Failed;
    #Refunded;
    #Processing;
  };
  
  public type Transaction = {
    id: TransactionId;
    transactionType: TransactionType;
    from: UserId;
    to: UserId;
    amount: Nat; // in satoshis
    fee: Nat; // platform fee
    taskId: ?TaskId;
    timestamp: Time.Time;
    status: TransactionStatus;
    txHash: ?Text; // Bitcoin transaction hash
    notes: ?Text;
  };
  
  public type Escrow = {
    taskId: TaskId;
    amount: Nat;
    payer: UserId;
    beneficiary: ?UserId;
    locked: Bool;
    createdAt: Time.Time;
    expiresAt: ?Time.Time;
  };
  
  public type WithdrawalRequest = {
    id: Nat;
    userId: UserId;
    amount: Nat;
    btcAddress: Text;
    requestedAt: Time.Time;
    processedAt: ?Time.Time;
    txHash: ?Text;
    status: TransactionStatus;
  };
  
  // Platform fee percentage (e.g., 5 = 5%)
  private stable var platformFeePercent : Nat = 5;
  private stable var minWithdrawal : Nat = 10000; // 10k sats minimum
  
  // Stable storage
  private stable var nextTxId : Nat = 0;
  private stable var nextWithdrawalId : Nat = 0;
  
  private stable var transactionEntries : [(TransactionId, Transaction)] = [];
  private var transactions = HashMap.HashMap<TransactionId, Transaction>(100, Nat.equal, Hash.hash);
  
  private stable var balanceEntries : [(UserId, Nat)] = [];
  private var balances = HashMap.HashMap<UserId, Nat>(100, Principal.equal, Principal.hash);
  
  private stable var escrowEntries : [(TaskId, Escrow)] = [];
  private var escrows = HashMap.HashMap<TaskId, Escrow>(100, Nat.equal, Hash.hash);
  
  private stable var withdrawalEntries : [(Nat, WithdrawalRequest)] = [];
  private var withdrawals = HashMap.HashMap<Nat, WithdrawalRequest>(100, Nat.equal, Hash.hash);
  
  private stable var userTransactionsEntries : [(UserId, [TransactionId])] = [];
  private var userTransactions = HashMap.HashMap<UserId, [TransactionId]>(100, Principal.equal, Principal.hash);
  
  // Upgrade hooks
  system func preupgrade() {
    transactionEntries := Iter.toArray(transactions.entries());
    balanceEntries := Iter.toArray(balances.entries());
    escrowEntries := Iter.toArray(escrows.entries());
    withdrawalEntries := Iter.toArray(withdrawals.entries());
    userTransactionsEntries := Iter.toArray(userTransactions.entries());
  };
  
  system func postupgrade() {
    transactions := HashMap.fromIter<TransactionId, Transaction>(transactionEntries.vals(), 100, Nat.equal, Hash.hash);
    balances := HashMap.fromIter<UserId, Nat>(balanceEntries.vals(), 100, Principal.equal, Principal.hash);
    escrows := HashMap.fromIter<TaskId, Escrow>(escrowEntries.vals(), 100, Nat.equal, Hash.hash);
    withdrawals := HashMap.fromIter<Nat, WithdrawalRequest>(withdrawalEntries.vals(), 100, Nat.equal, Hash.hash);
    userTransactions := HashMap.fromIter<UserId, [TransactionId]>(userTransactionsEntries.vals(), 100, Principal.equal, Principal.hash);
  };
  
  // Get user balance
  public query func getBalance(userId: UserId) : async Nat {
    switch(balances.get(userId)) {
      case(?balance) { balance };
      case(null) { 0 };
    }
  };
  
  // Get current user's balance
  public shared(msg) func getMyBalance() : async Nat {
    await getBalance(msg.caller)
  };
  
  // Calculate platform fee
  private func calculateFee(amount: Nat) : Nat {
    (amount * platformFeePercent) / 100
  };
  
  // Deposit satoshis (after Bitcoin payment confirmed)
  public shared(msg) func deposit(
    userId: UserId, 
    amount: Nat, 
    txHash: Text
  ) : async Result.Result<TransactionId, Text> {
    
    if (amount < 1000) {
      return #err("Minimum deposit is 1000 satoshis");
    };
    
    let txId = nextTxId;
    nextTxId += 1;
    
    let tx : Transaction = {
      id = txId;
      transactionType = #Deposit;
      from = userId;
      to = userId;
      amount = amount;
      fee = 0;
      taskId = null;
      timestamp = Time.now();
      status = #Completed;
      txHash = ?txHash;
      notes = ?"Bitcoin deposit";
    };
    
    transactions.put(txId, tx);
    
    let currentBalance = switch(balances.get(userId)) {
      case(?bal) { bal };
      case(null) { 0 };
    };
    balances.put(userId, currentBalance + amount);
    
    addUserTransaction(userId, txId);
    
    #ok(txId)
  };
  
  // Lock funds in escrow for task
  public shared(msg) func lockEscrow(
    taskId: TaskId, 
    amount: Nat,
    expiresAt: ?Time.Time
  ) : async Result.Result<(), Text> {
    let caller = msg.caller;
    
    if (Principal.isAnonymous(caller)) {
      return #err("Anonymous users cannot lock escrow");
    };
    
    let currentBalance = switch(balances.get(caller)) {
      case(?bal) { bal };
      case(null) { 0 };
    };
    
    if (currentBalance < amount) {
      return #err("Insufficient balance");
    };
    
    // Check if escrow already exists for this task
    switch(escrows.get(taskId)) {
      case(?existing) {
        if (existing.locked) {
          return #err("Escrow already locked for this task");
        };
      };
      case(null) {};
    };
    
    let escrow : Escrow = {
      taskId = taskId;
      amount = amount;
      payer = caller;
      beneficiary = null;
      locked = true;
      createdAt = Time.now();
      expiresAt = expiresAt;
    };
    
    escrows.put(taskId, escrow);
    balances.put(caller, currentBalance - amount);
    
    let txId = nextTxId;
    nextTxId += 1;
    
    let tx : Transaction = {
      id = txId;
      transactionType = #EscrowLock;
      from = caller;
      to = caller;
      amount = amount;
      fee = 0;
      taskId = ?taskId;
      timestamp = Time.now();
      status = #Completed;
      txHash = null;
      notes = ?"Funds locked in escrow";
    };
    
    transactions.put(txId, tx);
    addUserTransaction(caller, txId);
    
    #ok()
  };
  
  // Release escrow payment to worker
  public shared(msg) func releaseEscrow(
    taskId: TaskId, 
    worker: UserId
  ) : async Result.Result<TransactionId, Text> {
    let caller = msg.caller;
    
    switch(escrows.get(taskId)) {
      case(?escrow) {
        if (escrow.payer != caller) {
          return #err("Only the payer can release escrow");
        };
        
        if (not escrow.locked) {
          return #err("Escrow already released");
        };
        
        let fee = calculateFee(escrow.amount);
        let netAmount = escrow.amount - fee;
        
        let txId = nextTxId;
        nextTxId += 1;
        
        let tx : Transaction = {
          id = txId;
          transactionType = #TaskPayment;
          from = escrow.payer;
          to = worker;
          amount = netAmount;
          fee = fee;
          taskId = ?taskId;
          timestamp = Time.now();
          status = #Completed;
          txHash = null;
          notes = ?"Task payment released";
        };
        
        transactions.put(txId, tx);
        
        let workerBalance = switch(balances.get(worker)) {
          case(?bal) { bal };
          case(null) { 0 };
        };
        balances.put(worker, workerBalance + netAmount);
        
        let updated = { 
          escrow with 
          locked = false;
          beneficiary = ?worker;
        };
        escrows.put(taskId, updated);
        
        addUserTransaction(escrow.payer, txId);
        addUserTransaction(worker, txId);
        
        #ok(txId)
      };
      case(null) { #err("Escrow not found") };
    };
  };
  
  // Refund escrow (if task cancelled)
  public shared(msg) func refundEscrow(taskId: TaskId) : async Result.Result<TransactionId, Text> {
    let caller = msg.caller;
    
    switch(escrows.get(taskId)) {
      case(?escrow) {
        if (escrow.payer != caller) {
          return #err("Only the payer can refund escrow");
        };
        
        if (not escrow.locked) {
          return #err("Escrow already released");
        };
        
        let txId = nextTxId;
        nextTxId += 1;
        
        let tx : Transaction = {
          id = txId;
          transactionType = #Refund;
          from = caller;
          to = caller;
          amount = escrow.amount;
          fee = 0;
          taskId = ?taskId;
          timestamp = Time.now();
          status = #Completed;
          txHash = null;
          notes = ?"Escrow refunded";
        };
        
        transactions.put(txId, tx);
        
        let payerBalance = switch(balances.get(caller)) {
          case(?bal) { bal };
          case(null) { 0 };
        };
        balances.put(caller, payerBalance + escrow.amount);
        
        let updated = { escrow with locked = false };
        escrows.put(taskId, updated);
        
        addUserTransaction(caller, txId);
        
        #ok(txId)
      };
      case(null) { #err("Escrow not found") };
    };
  };
  
  // Request withdrawal
  public shared(msg) func requestWithdrawal(
    amount: Nat, 
    btcAddress: Text
  ) : async Result.Result<Nat, Text> {
    let caller = msg.caller;
    
    if (Principal.isAnonymous(caller)) {
      return #err("Anonymous users cannot withdraw");
    };
    
    if (amount < minWithdrawal) {
      return #err("Minimum withdrawal is " # Nat.toText(minWithdrawal) # " satoshis");
    };
    
    let currentBalance = switch(balances.get(caller)) {
      case(?bal) { bal };
      case(null) { 0 };
    };
    
    if (currentBalance < amount) {
      return #err("Insufficient balance");
    };
    
    let withdrawalId = nextWithdrawalId;
    nextWithdrawalId += 1;
    
    let withdrawal : WithdrawalRequest = {
      id = withdrawalId;
      userId = caller;
      amount = amount;
      btcAddress = btcAddress;
      requestedAt = Time.now();
      processedAt = null;
      txHash = null;
      status = #Pending;
    };
    
    withdrawals.put(withdrawalId, withdrawal);
    balances.put(caller, currentBalance - amount);
    
    let txId = nextTxId;
    nextTxId += 1;
    
    let tx : Transaction = {
      id = txId;
      transactionType = #Withdrawal;
      from = caller;
      to = caller;
      amount = amount;
      fee = 0;
      taskId = null;
      timestamp = Time.now();
      status = #Pending;
      txHash = null;
      notes = ?"Withdrawal request to " # btcAddress;
    };
    
    transactions.put(txId, tx);
    addUserTransaction(caller, txId);
    
    #ok(withdrawalId)
  };
  
  // Process withdrawal (admin function - would be called after Bitcoin tx)
  public func processWithdrawal(
    withdrawalId: Nat, 
    txHash: Text, 
    success: Bool
  ) : async Result.Result<(), Text> {
    
    switch(withdrawals.get(withdrawalId)) {
      case(?withdrawal) {
        if (withdrawal.status != #Pending) {
          return #err("Withdrawal already processed");
        };
        
        let status = if (success) { #Completed } else { #Failed };
        
        let updated = {
          withdrawal with
          processedAt = ?Time.now();
          txHash = if (success) { ?txHash } else { null };
          status = status;
        };
        
        withdrawals.put(withdrawalId, updated);
        
        // If failed, refund the balance
        if (not success) {
          let currentBalance = switch(balances.get(withdrawal.userId)) {
            case(?bal) { bal };
            case(null) { 0 };
          };
          balances.put(withdrawal.userId, currentBalance + withdrawal.amount);
        };
        
        #ok()
      };
      case(null) { #err("Withdrawal not found") };
    };
  };
  
  // Send bonus/tip to user
  public shared(msg) func sendBonus(
    recipient: UserId, 
    amount: Nat, 
    notes: Text
  ) : async Result.Result<TransactionId, Text> {
    let caller = msg.caller;
    
    if (Principal.isAnonymous(caller)) {
      return #err("Anonymous users cannot send bonuses");
    };
    
    let senderBalance = switch(balances.get(caller)) {
      case(?bal) { bal };
      case(null) { 0 };
    };
    
    if (senderBalance < amount) {
      return #err("Insufficient balance");
    };
    
    let txId = nextTxId;
    nextTxId += 1;
    
    let tx : Transaction = {
      id = txId;
      transactionType = #Bonus;
      from = caller;
      to = recipient;
      amount = amount;
      fee = 0;
      taskId = null;
      timestamp = Time.now();
      status = #Completed;
      txHash = null;
      notes = ?notes;
    };
    
    transactions.put(txId, tx);
    
    balances.put(caller, senderBalance - amount);
    
    let recipientBalance = switch(balances.get(recipient)) {
      case(?bal) { bal };
      case(null) { 0 };
    };
    balances.put(recipient, recipientBalance + amount);
    
    addUserTransaction(caller, txId);
    addUserTransaction(recipient, txId);
    
    #ok(txId)
  };
  
  // Get transaction by ID
  public query func getTransaction(txId: TransactionId) : async ?Transaction {
    transactions.get(txId)
  };
  
  // Get transaction history for user
  public query func getTransactionHistory(
    userId: UserId, 
    limit: Nat, 
    offset: Nat
  ) : async {
    transactions: [Transaction];
    total: Nat;
  } {
    switch(userTransactions.get(userId)) {
      case(?txIds) {
        let txs = Buffer.Buffer<Transaction>(txIds.size());
        for (id in txIds.vals()) {
          switch(transactions.get(id)) {
            case(?tx) { txs.add(tx) };
            case(null) {};
          };
        };
        
        let allTxs = Buffer.toArray(txs);
        let sorted = Array.sort(allTxs, func(a: Transaction, b: Transaction) : Order.Order {
          if (a.timestamp > b.timestamp) { #less }
          else if (a.timestamp < b.timestamp) { #greater }
          else { #equal }
        });
        
        let total = sorted.size();
        let start = if (offset >= total) { total } else { offset };
        let end = if (start + limit >= total) { total } else { start + limit };
        let count = end - start;
        
        let paginatedTxs = if (count > 0) {
          Array.tabulate<Transaction>(count, func(i) { sorted[start + i] })
        } else {
          []
        };
        
        {
          transactions = paginatedTxs;
          total = total;
        }
      };
      case(null) {
        {
          transactions = [];
          total = 0;
        }
      };
    };
  };
  
  // Get escrow details
  public query func getEscrow(taskId: TaskId) : async ?Escrow {
    escrows.get(taskId)
  };
  
  // Get withdrawal request
  public query func getWithdrawalRequest(withdrawalId: Nat) : async ?WithdrawalRequest {
    withdrawals.get(withdrawalId)
  };
  
  // Get user's withdrawal requests
  public query func getUserWithdrawals(userId: UserId) : async [WithdrawalRequest] {
    let allWithdrawals = Iter.toArray(withdrawals.vals());
    let userWithdrawals = Array.filter<WithdrawalRequest>(allWithdrawals, func(w) {
      w.userId == userId
    });
    
    Array.sort(userWithdrawals, func(a: WithdrawalRequest, b: WithdrawalRequest) : Order.Order {
      if (a.requestedAt > b.requestedAt) { #less }
      else if (a.requestedAt < b.requestedAt) { #greater }
      else { #equal }
    })
  };
  
  // Helper: Add transaction to user's history
  private func addUserTransaction(userId: UserId, txId: TransactionId) {
    let existing = switch(userTransactions.get(userId)) {
      case(?ids) { ids };
      case(null) { [] };
    };
    userTransactions.put(userId, Array.append(existing, [txId]));
  };
  
  // Get payment statistics
  public query func getPaymentStats() : async {
    totalTransactions: Nat;
    totalVolume: Nat;
    totalFees: Nat;
    activeEscrows: Nat;
    totalEscrowAmount: Nat;
    pendingWithdrawals: Nat;
  } {
    let allTxs = Iter.toArray(transactions.vals());
    var totalVolume = 0;
    var totalFees = 0;
    
    for (tx in allTxs.vals()) {
      totalVolume += tx.amount;
      totalFees += tx.fee;
    };
    
    let allEscrows = Iter.toArray(escrows.vals());
    var activeEscrowCount = 0;
    var totalEscrowAmount = 0;
    
    for (escrow in allEscrows.vals()) {
      if (escrow.locked) {
        activeEscrowCount += 1;
        totalEscrowAmount += escrow.amount;
      };
    };
    
    let allWithdrawals = Iter.toArray(withdrawals.vals());
    var pendingCount = 0;
    
    for (withdrawal in allWithdrawals.vals()) {
      if (withdrawal.status == #Pending) {
        pendingCount += 1;
      };
    };
    
    {
      totalTransactions = allTxs.size();
      totalVolume = totalVolume;
      totalFees = totalFees;
      activeEscrows = activeEscrowCount;
      totalEscrowAmount = totalEscrowAmount;
      pendingWithdrawals = pendingCount;
    }
  };
  
  // Get platform fee percentage
  public query func getPlatformFee() : async Nat {
    platformFeePercent
  };
  
  // Update platform fee (admin only)
  public func updatePlatformFee(newFee: Nat) : async Result.Result<(), Text> {
    if (newFee > 20) {
      return #err("Fee cannot exceed 20%");
    };
    platformFeePercent := newFee;
    #ok()
  };
};