// ============================================
// FILE: src/canisters/DisputeCanister.mo
// Handles task disputes and resolution
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
import Text "mo:base/Text";

actor DisputeCanister {
  
  type DisputeId = Nat;
  type TaskId = Nat;
  type UserId = Principal;
  type MessageId = Nat;
  
  public type DisputeStatus = {
    #Open;
    #UnderReview;
    #AwaitingEvidence;
    #Resolved;
    #Escalated;
    #Closed;
  };
  
  public type DisputeReason = {
    #IncompleteWork;
    #LateSubmission;
    #QualityIssues;
    #InstructionsUnclear;
    #PaymentIssue;
    #Other: Text;
  };
  
  public type DisputeResolution = {
    #FavorCreator;
    #FavorWorker;
    #Split: Nat; // Percentage to worker (0-100)
    #Refund;
  };
  
  public type Dispute = {
    id: DisputeId;
    taskId: TaskId;
    creator: UserId; // Task creator
    worker: UserId; // Task worker
    initiatedBy: UserId;
    reason: DisputeReason;
    description: Text;
    createdAt: Time.Time;
    status: DisputeStatus;
    resolution: ?DisputeResolution;
    resolvedAt: ?Time.Time;
    resolvedBy: ?UserId;
    resolutionNotes: ?Text;
    evidenceUrls: [Text];
  };
  
  public type DisputeMessage = {
    id: MessageId;
    disputeId: DisputeId;
    sender: UserId;
    message: Text;
    timestamp: Time.Time;
    attachments: [Text];
  };
  
  public type Evidence = {
    disputeId: DisputeId;
    submittedBy: UserId;
    description: Text;
    urls: [Text];
    submittedAt: Time.Time;
  };
  
  // Stable storage
  private stable var nextDisputeId : Nat = 0;
  private stable var nextMessageId : Nat = 0;
  
  private stable var disputeEntries : [(DisputeId, Dispute)] = [];
  private var disputes = HashMap.HashMap<DisputeId, Dispute>(50, Nat.equal, Hash.hash);
  
  private stable var taskDisputeEntries : [(TaskId, DisputeId)] = [];
  private var taskDisputes = HashMap.HashMap<TaskId, DisputeId>(50, Nat.equal, Hash.hash);
  
  private stable var messageEntries : [(DisputeId, [DisputeMessage])] = [];
  private var messages = HashMap.HashMap<DisputeId, [DisputeMessage]>(50, Nat.equal, Hash.hash);
  
  private stable var evidenceEntries : [(DisputeId, [Evidence])] = [];
  private var evidence = HashMap.HashMap<DisputeId, [Evidence]>(50, Nat.equal, Hash.hash);
  
  private stable var userDisputesEntries : [(UserId, [DisputeId])] = [];
  private var userDisputes = HashMap.HashMap<UserId, [DisputeId]>(50, Principal.equal, Principal.hash);
  
  // Upgrade hooks
  system func preupgrade() {
    disputeEntries := Iter.toArray(disputes.entries());
    taskDisputeEntries := Iter.toArray(taskDisputes.entries());
    messageEntries := Iter.toArray(messages.entries());
    evidenceEntries := Iter.toArray(evidence.entries());
    userDisputesEntries := Iter.toArray(userDisputes.entries());
  };
  
  system func postupgrade() {
    disputes := HashMap.fromIter<DisputeId, Dispute>(disputeEntries.vals(), 50, Nat.equal, Hash.hash);
    taskDisputes := HashMap.fromIter<TaskId, DisputeId>(taskDisputeEntries.vals(), 50, Nat.equal, Hash.hash);
    messages := HashMap.fromIter<DisputeId, [DisputeMessage]>(messageEntries.vals(), 50, Nat.equal, Hash.hash);
    evidence := HashMap.fromIter<DisputeId, [Evidence]>(evidenceEntries.vals(), 50, Nat.equal, Hash.hash);
    userDisputes := HashMap.fromIter<UserId, [DisputeId]>(userDisputesEntries.vals(), 50, Principal.equal, Principal.hash);
  };
  
  // Create a new dispute
  public shared(msg) func createDispute(
    taskId: TaskId,
    creator: UserId,
    worker: UserId,
    reason: DisputeReason,
    description: Text,
    evidenceUrls: [Text]
  ) : async Result.Result<DisputeId, Text> {
    let caller = msg.caller;
    
    if (Principal.isAnonymous(caller)) {
      return #err("Anonymous users cannot create disputes");
    };
    
    // Check if caller is involved in the task
    if (caller != creator and caller != worker) {
      return #err("Only task participants can create disputes");
    };
    
    // Check if dispute already exists for this task
    switch(taskDisputes.get(taskId)) {
      case(?existingId) {
        return #err("Dispute already exists for this task");
      };
      case(null) {};
    };
    
    if (Text.size(description) < 20) {
      return #err("Description must be at least 20 characters");
    };
    
    let disputeId = nextDisputeId;
    nextDisputeId += 1;
    
    let dispute : Dispute = {
      id = disputeId;
      taskId = taskId;
      creator = creator;
      worker = worker;
      initiatedBy = caller;
      reason = reason;
      description = description;
      createdAt = Time.now();
      status = #Open;
      resolution = null;
      resolvedAt = null;
      resolvedBy = null;
      resolutionNotes = null;
      evidenceUrls = evidenceUrls;
    };
    
    disputes.put(disputeId, dispute);
    taskDisputes.put(taskId, disputeId);
    messages.put(disputeId, []);
    evidence.put(disputeId, []);
    
    // Add to both users' dispute lists
    addUserDispute(creator, disputeId);
    addUserDispute(worker, disputeId);
    
    #ok(disputeId)
  };
  
  // Get dispute by ID
  public query func getDispute(disputeId: DisputeId) : async ?Dispute {
    disputes.get(disputeId)
  };
  
  // Get dispute by task ID
  public query func getDisputeByTask(taskId: TaskId) : async ?Dispute {
    switch(taskDisputes.get(taskId)) {
      case(?disputeId) { disputes.get(disputeId) };
      case(null) { null };
    };
  };
  
  // Add message to dispute
  public shared(msg) func addMessage(
    disputeId: DisputeId,
    message: Text,
    attachments: [Text]
  ) : async Result.Result<MessageId, Text> {
    let caller = msg.caller;
    
    if (Principal.isAnonymous(caller)) {
      return #err("Anonymous users cannot add messages");
    };
    
    switch(disputes.get(disputeId)) {
      case(?dispute) {
        // Check if caller is involved
        if (caller != dispute.creator and caller != dispute.worker) {
          return #err("Only dispute participants can add messages");
        };
        
        if (dispute.status == #Resolved or dispute.status == #Closed) {
          return #err("Cannot add messages to closed dispute");
        };
        
        if (Text.size(message) == 0) {
          return #err("Message cannot be empty");
        };
        
        let messageId = nextMessageId;
        nextMessageId += 1;
        
        let disputeMessage : DisputeMessage = {
          id = messageId;
          disputeId = disputeId;
          sender = caller;
          message = message;
          timestamp = Time.now();
          attachments = attachments;
        };
        
        let existing = switch(messages.get(disputeId)) {
          case(?msgs) { msgs };
          case(null) { [] };
        };
        messages.put(disputeId, Array.append(existing, [disputeMessage]));
        
        #ok(messageId)
      };
      case(null) { #err("Dispute not found") };
    };
  };
  
  // Submit evidence
  public shared(msg) func submitEvidence(
    disputeId: DisputeId,
    description: Text,
    urls: [Text]
  ) : async Result.Result<(), Text> {
    let caller = msg.caller;
    
    if (Principal.isAnonymous(caller)) {
      return #err("Anonymous users cannot submit evidence");
    };
    
    switch(disputes.get(disputeId)) {
      case(?dispute) {
        if (caller != dispute.creator and caller != dispute.worker) {
          return #err("Only dispute participants can submit evidence");
        };
        
        if (dispute.status == #Resolved or dispute.status == #Closed) {
          return #err("Cannot submit evidence to closed dispute");
        };
        
        let newEvidence : Evidence = {
          disputeId = disputeId;
          submittedBy = caller;
          description = description;
          urls = urls;
          submittedAt = Time.now();
        };
        
        let existing = switch(evidence.get(disputeId)) {
          case(?evs) { evs };
          case(null) { [] };
        };
        evidence.put(disputeId, Array.append(existing, [newEvidence]));
        
        #ok()
      };
      case(null) { #err("Dispute not found") };
    };
  };
  
  // Update dispute status
  public shared(msg) func updateDisputeStatus(
    disputeId: DisputeId,
    newStatus: DisputeStatus
  ) : async Result.Result<(), Text> {
    // In production, check if caller is admin
    
    switch(disputes.get(disputeId)) {
      case(?dispute) {
        if (dispute.status == #Closed) {
          return #err("Cannot update closed dispute");
        };
        
        let updated = { dispute with status = newStatus };
        disputes.put(disputeId, updated);
        #ok()
      };
      case(null) { #err("Dispute not found") };
    };
  };
  
  // Resolve dispute
  public shared(msg) func resolveDispute(
    disputeId: DisputeId,
    resolution: DisputeResolution,
    notes: Text
  ) : async Result.Result<(), Text> {
    let caller = msg.caller;
    // In production, check if caller is admin/moderator
    
    switch(disputes.get(disputeId)) {
      case(?dispute) {
        if (dispute.status == #Resolved or dispute.status == #Closed) {
          return #err("Dispute already resolved");
        };
        
        let updated = {
          dispute with
          status = #Resolved;
          resolution = ?resolution;
          resolvedAt = ?Time.now();
          resolvedBy = ?caller;
          resolutionNotes = ?notes;
        };
        
        disputes.put(disputeId, updated);
        #ok()
      };
      case(null) { #err("Dispute not found") };
    };
  };
  
  // Close dispute
  public shared(msg) func closeDispute(disputeId: DisputeId) : async Result.Result<(), Text> {
    // In production, check if caller is admin
    
    switch(disputes.get(disputeId)) {
      case(?dispute) {
        if (dispute.status != #Resolved) {
          return #err("Can only close resolved disputes");
        };
        
        let updated = { dispute with status = #Closed };
        disputes.put(disputeId, updated);
        #ok()
      };
      case(null) { #err("Dispute not found") };
    };
  };
  
  // Get dispute messages
  public query func getDisputeMessages(disputeId: DisputeId) : async [DisputeMessage] {
    switch(messages.get(disputeId)) {
      case(?msgs) {
        Array.sort(msgs, func(a: DisputeMessage, b: DisputeMessage) : Order.Order {
          if (a.timestamp < b.timestamp) { #less }
          else if (a.timestamp > b.timestamp) { #greater }
          else { #equal }
        })
      };
      case(null) { [] };
    };
  };
  
  // Get dispute evidence
  public query func getDisputeEvidence(disputeId: DisputeId) : async [Evidence] {
    switch(evidence.get(disputeId)) {
      case(?evs) {
        Array.sort(evs, func(a: Evidence, b: Evidence) : Order.Order {
          if (a.submittedAt < b.submittedAt) { #less }
          else if (a.submittedAt > b.submittedAt) { #greater }
          else { #equal }
        })
      };
      case(null) { [] };
    };
  };
  
  // Get user's disputes
  public query func getUserDisputes(userId: UserId) : async [Dispute] {
    switch(userDisputes.get(userId)) {
      case(?disputeIds) {
        let buf = Buffer.Buffer<Dispute>(disputeIds.size());
        for (id in disputeIds.vals()) {
          switch(disputes.get(id)) {
            case(?dispute) { buf.add(dispute) };
            case(null) {};
          };
        };
        
        let allDisputes = Buffer.toArray(buf);
        Array.sort(allDisputes, func(a: Dispute, b: Dispute) : Order.Order {
          if (a.createdAt > b.createdAt) { #less }
          else if (a.createdAt < b.createdAt) { #greater }
          else { #equal }
        })
      };
      case(null) { [] };
    };
  };
  
  // Get all open disputes (admin view)
  public query func getOpenDisputes(limit: Nat) : async [Dispute] {
    let allDisputes = Iter.toArray(disputes.vals());
    let openDisputes = Array.filter<Dispute>(allDisputes, func(d) {
      d.status == #Open or d.status == #UnderReview or d.status == #AwaitingEvidence
    });
    
    let sorted = Array.sort(openDisputes, func(a: Dispute, b: Dispute) : Order.Order {
      if (a.createdAt < b.createdAt) { #less }
      else if (a.createdAt > b.createdAt) { #greater }
      else { #equal }
    });
    
    let actualLimit = if (sorted.size() < limit) { sorted.size() } else { limit };
    Array.tabulate<Dispute>(actualLimit, func(i) { sorted[i] })
  };
  
  // Get dispute statistics
  public query func getDisputeStats() : async {
    totalDisputes: Nat;
    openDisputes: Nat;
    resolvedDisputes: Nat;
    favorCreatorCount: Nat;
    favorWorkerCount: Nat;
    splitResolutionCount: Nat;
    averageResolutionTime: Nat;
  } {
    let allDisputes = Iter.toArray(disputes.vals());
    var openCount = 0;
    var resolvedCount = 0;
    var favorCreatorCount = 0;
    var favorWorkerCount = 0;
    var splitCount = 0;
    var totalResolutionTime : Nat = 0;
    
    for (dispute in allDisputes.vals()) {
      if (dispute.status == #Open or dispute.status == #UnderReview or dispute.status == #AwaitingEvidence) {
        openCount += 1;
      };
      
      if (dispute.status == #Resolved or dispute.status == #Closed) {
        resolvedCount += 1;
        
        switch(dispute.resolution) {
          case(?#FavorCreator) { favorCreatorCount += 1 };
          case(?#FavorWorker) { favorWorkerCount += 1 };
          case(?#Split(_)) { splitCount += 1 };
          case(_) {};
        };
        
        switch(dispute.resolvedAt) {
          case(?resolved) {
            let duration = resolved - dispute.createdAt;
            totalResolutionTime += duration / 1_000_000_000; // Convert to seconds
          };
          case(null) {};
        };
      };
    };
    
    let avgResolutionTime = if (resolvedCount > 0) {
      totalResolutionTime / resolvedCount
    } else {
      0
    };
    
    {
      totalDisputes = allDisputes.size();
      openDisputes = openCount;
      resolvedDisputes = resolvedCount;
      favorCreatorCount = favorCreatorCount;
      favorWorkerCount = favorWorkerCount;
      splitResolutionCount = splitCount;
      averageResolutionTime = avgResolutionTime;
    }
  };
  
  // Helper: Add dispute to user's list
  private func addUserDispute(userId: UserId, disputeId: DisputeId) {
    let existing = switch(userDisputes.get(userId)) {
      case(?ids) { ids };
      case(null) { [] };
    };
    
    // Check if not already added
    let alreadyExists = Array.find<DisputeId>(existing, func(id) { id == disputeId }) != null;
    if (not alreadyExists) {
      userDisputes.put(userId, Array.append(existing, [disputeId]));
    };
  };
};