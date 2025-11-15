// ============================================
// FILE: src/canisters/TaskCanister.mo
// Manages task creation, assignment, and completion
// ============================================

import Principal "mo:base/Principal";
import HashMap "mo:base/HashMap";
import Hash "mo:base/Hash";
import Iter "mo:base/Iter";
import Time "mo:base/Time";
import Nat "mo:base/Nat";
import Result "mo:base/Result";
import Array "mo:base/Array";
import Order "mo:base/Order";
import Buffer "mo:base/Buffer";
import Option "mo:base/Option";
import Text "mo:base/Text";

actor TaskCanister {
  
  type TaskId = Nat;
  type UserId = Principal;
  
  public type TaskType = {
    #Survey;
    #DataLabeling;
    #Feedback;
    #ContentModeration;
    #Transcription;
    #ImageAnnotation;
    #TextClassification;
    #Other: Text;
  };
  
  public type TaskStatus = {
    #Open;
    #Assigned;
    #InProgress;
    #Submitted;
    #UnderReview;
    #Completed;
    #Disputed;
    #Cancelled;
    #Expired;
  };
  
  public type Difficulty = {
    #Easy;
    #Medium;
    #Hard;
  };
  
  public type Task = {
    id: TaskId;
    creator: UserId;
    title: Text;
    description: Text;
    instructions: Text;
    taskType: TaskType;
    difficulty: Difficulty;
    reward: Nat; // in satoshis
    requiredSkills: [Text];
    timeEstimate: Nat; // in minutes
    createdAt: Time.Time;
    deadline: ?Time.Time;
    status: TaskStatus;
    assignedTo: ?UserId;
    assignedAt: ?Time.Time;
    submissionUrl: ?Text;
    submittedAt: ?Time.Time;
    completedAt: ?Time.Time;
    reviewScore: ?Nat; // 1-5
    reviewComment: ?Text;
    maxWorkers: Nat;
    currentWorkers: Nat;
    tags: [Text];
    attachmentUrls: [Text];
  };
  
  public type TaskSubmission = {
    taskId: TaskId;
    worker: UserId;
    submissionUrl: Text;
    submittedAt: Time.Time;
    notes: ?Text;
    attachments: [Text];
  };
  
  public type TaskFilter = {
    taskType: ?TaskType;
    difficulty: ?Difficulty;
    minReward: ?Nat;
    maxReward: ?Nat;
    skills: ?[Text];
    tags: ?[Text];
    creator: ?UserId;
  };
  
  public type TaskReview = {
    taskId: TaskId;
    reviewer: UserId;
    worker: UserId;
    score: Nat; // 1-5
    comment: ?Text;
    reviewedAt: Time.Time;
    approved: Bool;
  };
  
  // Stable storage
  private stable var nextTaskId : Nat = 0;
  private stable var taskEntries : [(TaskId, Task)] = [];
  private var tasks = HashMap.HashMap<TaskId, Task>(100, Nat.equal, Hash.hash);
  
  private stable var submissionEntries : [(TaskId, [TaskSubmission])] = [];
  private var submissions = HashMap.HashMap<TaskId, [TaskSubmission]>(100, Nat.equal, Hash.hash);
  
  private stable var reviewEntries : [(TaskId, [TaskReview])] = [];
  private var reviews = HashMap.HashMap<TaskId, [TaskReview]>(100, Nat.equal, Hash.hash);
  
  private stable var userCreatedTasksEntries : [(UserId, [TaskId])] = [];
  private var userCreatedTasks = HashMap.HashMap<UserId, [TaskId]>(100, Principal.equal, Principal.hash);
  
  private stable var userAssignedTasksEntries : [(UserId, [TaskId])] = [];
  private var userAssignedTasks = HashMap.HashMap<UserId, [TaskId]>(100, Principal.equal, Principal.hash);
  
  // Upgrade hooks
  system func preupgrade() {
    taskEntries := Iter.toArray(tasks.entries());
    submissionEntries := Iter.toArray(submissions.entries());
    reviewEntries := Iter.toArray(reviews.entries());
    userCreatedTasksEntries := Iter.toArray(userCreatedTasks.entries());
    userAssignedTasksEntries := Iter.toArray(userAssignedTasks.entries());
  };
  
  system func postupgrade() {
    tasks := HashMap.fromIter<TaskId, Task>(taskEntries.vals(), 100, Nat.equal, Hash.hash);
    submissions := HashMap.fromIter<TaskId, [TaskSubmission]>(submissionEntries.vals(), 100, Nat.equal, Hash.hash);
    reviews := HashMap.fromIter<TaskId, [TaskReview]>(reviewEntries.vals(), 100, Nat.equal, Hash.hash);
    userCreatedTasks := HashMap.fromIter<UserId, [TaskId]>(userCreatedTasksEntries.vals(), 100, Principal.equal, Principal.hash);
    userAssignedTasks := HashMap.fromIter<UserId, [TaskId]>(userAssignedTasksEntries.vals(), 100, Principal.equal, Principal.hash);
  };
  
  // Create a new task
  public shared(msg) func createTask(
    title: Text,
    description: Text,
    instructions: Text,
    taskType: TaskType,
    difficulty: Difficulty,
    reward: Nat,
    requiredSkills: [Text],
    timeEstimate: Nat,
    deadline: ?Time.Time,
    maxWorkers: Nat,
    tags: [Text],
    attachmentUrls: [Text]
  ) : async Result.Result<TaskId, Text> {
    let caller = msg.caller;
    
    if (Principal.isAnonymous(caller)) {
      return #err("Anonymous users cannot create tasks");
    };
    
    if (reward < 100) {
      return #err("Minimum reward is 100 satoshis");
    };
    
    if (Text.size(title) < 5 or Text.size(title) > 100) {
      return #err("Title must be between 5 and 100 characters");
    };
    
    if (Text.size(description) < 10) {
      return #err("Description must be at least 10 characters");
    };
    
    if (maxWorkers < 1) {
      return #err("Must allow at least 1 worker");
    };
    
    let taskId = nextTaskId;
    nextTaskId += 1;
    
    let task : Task = {
      id = taskId;
      creator = caller;
      title = title;
      description = description;
      instructions = instructions;
      taskType = taskType;
      difficulty = difficulty;
      reward = reward;
      requiredSkills = requiredSkills;
      timeEstimate = timeEstimate;
      createdAt = Time.now();
      deadline = deadline;
      status = #Open;
      assignedTo = null;
      assignedAt = null;
      submissionUrl = null;
      submittedAt = null;
      completedAt = null;
      reviewScore = null;
      reviewComment = null;
      maxWorkers = maxWorkers;
      currentWorkers = 0;
      tags = tags;
      attachmentUrls = attachmentUrls;
    };
    
    tasks.put(taskId, task);
    
    let existing = switch(userCreatedTasks.get(caller)) {
      case(?ids) { ids };
      case(null) { [] };
    };
    userCreatedTasks.put(caller, Array.append(existing, [taskId]));
    
    #ok(taskId)
  };
  
  // Get task by ID
  public query func getTask(taskId: TaskId) : async ?Task {
    tasks.get(taskId)
  };
  
  // Get multiple tasks
  public query func getTasks(taskIds: [TaskId]) : async [Task] {
    let buf = Buffer.Buffer<Task>(taskIds.size());
    for (id in taskIds.vals()) {
      switch(tasks.get(id)) {
        case(?task) { buf.add(task) };
        case(null) {};
      };
    };
    Buffer.toArray(buf)
  };
  
  // Get available tasks with filters
  public query func getAvailableTasks(filter: ?TaskFilter, limit: Nat, offset: Nat) : async {
    tasks: [Task];
    total: Nat;
  } {
    let allTasks = Iter.toArray(tasks.vals());
    
    let filtered = Array.filter<Task>(allTasks, func(task) {
      if (task.status != #Open) { return false };
      
      // Check deadline
      switch(task.deadline) {
        case(?dl) {
          if (dl < Time.now()) { return false };
        };
        case(null) {};
      };
      
      switch(filter) {
        case(?f) {
          // Filter by task type
          switch(f.taskType) {
            case(?tt) { if (task.taskType != tt) { return false } };
            case(null) {};
          };
          
          // Filter by difficulty
          switch(f.difficulty) {
            case(?d) { if (task.difficulty != d) { return false } };
            case(null) {};
          };
          
          // Filter by min reward
          switch(f.minReward) {
            case(?min) { if (task.reward < min) { return false } };
            case(null) {};
          };
          
          // Filter by max reward
          switch(f.maxReward) {
            case(?max) { if (task.reward > max) { return false } };
            case(null) {};
          };
          
          // Filter by creator
          switch(f.creator) {
            case(?c) { if (task.creator != c) { return false } };
            case(null) {};
          };
          
          // Filter by skills
          switch(f.skills) {
            case(?skills) {
              var hasSkill = false;
              for (reqSkill in task.requiredSkills.vals()) {
                for (userSkill in skills.vals()) {
                  if (reqSkill == userSkill) {
                    hasSkill := true;
                  };
                };
              };
              if (not hasSkill and task.requiredSkills.size() > 0) { return false };
            };
            case(null) {};
          };
          
          // Filter by tags
          switch(f.tags) {
            case(?tags) {
              var hasTag = false;
              for (taskTag in task.tags.vals()) {
                for (filterTag in tags.vals()) {
                  if (taskTag == filterTag) {
                    hasTag := true;
                  };
                };
              };
              if (not hasTag and tags.size() > 0) { return false };
            };
            case(null) {};
          };
          
          true
        };
        case(null) { true };
      }
    });
    
    // Sort by reward (highest first)
    let sorted = Array.sort(filtered, func(a: Task, b: Task) : Order.Order {
      if (a.reward > b.reward) { #less }
      else if (a.reward < b.reward) { #greater }
      else { #equal }
    });
    
    let total = sorted.size();
    let start = if (offset >= total) { total } else { offset };
    let end = if (start + limit >= total) { total } else { start + limit };
    let count = end - start;
    
    let paginatedTasks = if (count > 0) {
      Array.tabulate<Task>(count, func(i) { sorted[start + i] })
    } else {
      []
    };
    
    {
      tasks = paginatedTasks;
      total = total;
    }
  };
  
  // Assign task to worker
  public shared(msg) func assignTask(taskId: TaskId) : async Result.Result<(), Text> {
    let caller = msg.caller;
    
    if (Principal.isAnonymous(caller)) {
      return #err("Anonymous users cannot accept tasks");
    };
    
    switch(tasks.get(taskId)) {
      case(?task) {
        if (task.status != #Open) {
          return #err("Task is not available");
        };
        
        if (task.creator == caller) {
          return #err("Cannot assign your own task");
        };
        
        // Check deadline
        switch(task.deadline) {
          case(?dl) {
            if (dl < Time.now()) {
              return #err("Task deadline has passed");
            };
          };
          case(null) {};
        };
        
        let updated = {
          task with 
          status = #Assigned;
          assignedTo = ?caller;
          assignedAt = ?Time.now();
        };
        tasks.put(taskId, updated);
        
        let existing = switch(userAssignedTasks.get(caller)) {
          case(?ids) { ids };
          case(null) { [] };
        };
        userAssignedTasks.put(caller, Array.append(existing, [taskId]));
        
        #ok()
      };
      case(null) { #err("Task not found") };
    };
  };
  
  // Start working on task
  public shared(msg) func startTask(taskId: TaskId) : async Result.Result<(), Text> {
    let caller = msg.caller;
    
    switch(tasks.get(taskId)) {
      case(?task) {
        switch(task.assignedTo) {
          case(?assignee) {
            if (assignee != caller) {
              return #err("Not assigned to you");
            };
            
            if (task.status != #Assigned) {
              return #err("Task already started or completed");
            };
            
            let updated = { task with status = #InProgress };
            tasks.put(taskId, updated);
            #ok()
          };
          case(null) { #err("Task not assigned") };
        };
      };
      case(null) { #err("Task not found") };
    };
  };
  
  // Submit completed task
  public shared(msg) func submitTask(
    taskId: TaskId,
    submissionUrl: Text,
    notes: ?Text,
    attachments: [Text]
  ) : async Result.Result<(), Text> {
    let caller = msg.caller;
    
    if (Text.size(submissionUrl) == 0) {
      return #err("Submission URL cannot be empty");
    };
    
    switch(tasks.get(taskId)) {
      case(?task) {
        switch(task.assignedTo) {
          case(?assignee) {
            if (assignee != caller) {
              return #err("Not authorized to submit this task");
            };
            
            if (task.status != #InProgress and task.status != #Assigned) {
              return #err("Task cannot be submitted in current status");
            };
            
            let submission : TaskSubmission = {
              taskId = taskId;
              worker = caller;
              submissionUrl = submissionUrl;
              submittedAt = Time.now();
              notes = notes;
              attachments = attachments;
            };
            
            let existing = switch(submissions.get(taskId)) {
              case(?subs) { subs };
              case(null) { [] };
            };
            submissions.put(taskId, Array.append(existing, [submission]));
            
            let updated = {
              task with 
              status = #Submitted;
              submissionUrl = ?submissionUrl;
              submittedAt = ?Time.now();
            };
            tasks.put(taskId, updated);
            #ok()
          };
          case(null) { #err("Task not assigned") };
        };
      };
      case(null) { #err("Task not found") };
    };
  };
  
  // Review and approve/reject task
  public shared(msg) func reviewTask(
    taskId: TaskId,
    approved: Bool,
    score: Nat,
    comment: ?Text
  ) : async Result.Result<(), Text> {
    let caller = msg.caller;
    
    if (score < 1 or score > 5) {
      return #err("Score must be between 1 and 5");
    };
    
    switch(tasks.get(taskId)) {
      case(?task) {
        if (task.creator != caller) {
          return #err("Only task creator can review");
        };
        
        if (task.status != #Submitted and task.status != #UnderReview) {
          return #err("Task is not ready for review");
        };
        
        switch(task.assignedTo) {
          case(?worker) {
            let review : TaskReview = {
              taskId = taskId;
              reviewer = caller;
              worker = worker;
              score = score;
              comment = comment;
              reviewedAt = Time.now();
              approved = approved;
            };
            
            let existing = switch(reviews.get(taskId)) {
              case(?revs) { revs };
              case(null) { [] };
            };
            reviews.put(taskId, Array.append(existing, [review]));
            
            let updated = {
              task with 
              status = if (approved) { #Completed } else { #Disputed };
              completedAt = if (approved) { ?Time.now() } else { null };
              reviewScore = if (approved) { ?score } else { null };
              reviewComment = comment;
            };
            tasks.put(taskId, updated);
            #ok()
          };
          case(null) { #err("Task not assigned to any worker") };
        };
      };
      case(null) { #err("Task not found") };
    };
  };
  
  // Cancel task
  public shared(msg) func cancelTask(taskId: TaskId, reason: Text) : async Result.Result<(), Text> {
    let caller = msg.caller;
    
    switch(tasks.get(taskId)) {
      case(?task) {
        if (task.creator != caller) {
          return #err("Only creator can cancel task");
        };
        
        if (task.status == #Completed or task.status == #Disputed) {
          return #err("Cannot cancel completed or disputed task");
        };
        
        let updated = { 
          task with 
          status = #Cancelled;
          reviewComment = ?reason;
        };
        tasks.put(taskId, updated);
        #ok()
      };
      case(null) { #err("Task not found") };
    };
  };
  
  // Unassign from task (worker cancels)
  public shared(msg) func unassignTask(taskId: TaskId) : async Result.Result<(), Text> {
    let caller = msg.caller;
    
    switch(tasks.get(taskId)) {
      case(?task) {
        switch(task.assignedTo) {
          case(?assignee) {
            if (assignee != caller) {
              return #err("Not assigned to you");
            };
            
            if (task.status == #Submitted or task.status == #UnderReview or task.status == #Completed) {
              return #err("Cannot unassign after submission");
            };
            
            let updated = {
              task with 
              status = #Open;
              assignedTo = null;
              assignedAt = null;
            };
            tasks.put(taskId, updated);
            #ok()
          };
          case(null) { #err("Task not assigned") };
        };
      };
      case(null) { #err("Task not found") };
    };
  };
  
  // Get tasks created by user
  public query func getUserCreatedTasks(userId: UserId) : async [Task] {
    switch(userCreatedTasks.get(userId)) {
      case(?taskIds) {
        let buf = Buffer.Buffer<Task>(taskIds.size());
        for (id in taskIds.vals()) {
          switch(tasks.get(id)) {
            case(?task) { buf.add(task) };
            case(null) {};
          };
        };
        Buffer.toArray(buf)
      };
      case(null) { [] };
    };
  };
  
  // Get tasks assigned to user
  public query func getUserAssignedTasks(userId: UserId) : async [Task] {
    switch(userAssignedTasks.get(userId)) {
      case(?taskIds) {
        let buf = Buffer.Buffer<Task>(taskIds.size());
        for (id in taskIds.vals()) {
          switch(tasks.get(id)) {
            case(?task) { buf.add(task) };
            case(null) {};
          };
        };
        Buffer.toArray(buf)
      };
      case(null) { [] };
    };
  };
  
  // Get task submissions
  public query func getTaskSubmissions(taskId: TaskId) : async [TaskSubmission] {
    switch(submissions.get(taskId)) {
      case(?subs) { subs };
      case(null) { [] };
    };
  };
  
  // Get task reviews
  public query func getTaskReviews(taskId: TaskId) : async [TaskReview] {
    switch(reviews.get(taskId)) {
      case(?revs) { revs };
      case(null) { [] };
    };
  };
  
  // Get tasks by type
  public query func getTasksByType(taskType: TaskType, limit: Nat) : async [Task] {
    let allTasks = Iter.toArray(tasks.vals());
    let filtered = Array.filter<Task>(allTasks, func(task) {
      task.taskType == taskType and task.status == #Open
    });
    
    let sorted = Array.sort(filtered, func(a: Task, b: Task) : Order.Order {
      if (a.createdAt > b.createdAt) { #less }
      else if (a.createdAt < b.createdAt) { #greater }
      else { #equal }
    });
    
    let actualLimit = if (sorted.size() < limit) { sorted.size() } else { limit };
    Array.tabulate<Task>(actualLimit, func(i) { sorted[i] })
  };
  
  // Get platform statistics
  public query func getTaskStats() : async {
    totalTasks: Nat;
    openTasks: Nat;
    assignedTasks: Nat;
    completedTasks: Nat;
    totalReward: Nat;
    averageReward: Nat;
  } {
    let allTasks = Iter.toArray(tasks.vals());
    var openCount = 0;
    var assignedCount = 0;
    var completedCount = 0;
    var totalReward = 0;
    
    for (task in allTasks.vals()) {
      if (task.status == #Open) { openCount += 1 };
      if (task.status == #Assigned or task.status == #InProgress) { assignedCount += 1 };
      if (task.status == #Completed) { completedCount += 1 };
      totalReward += task.reward;
    };
    
    let avgReward = if (allTasks.size() > 0) {
      totalReward / allTasks.size()
    } else {
      0
    };
    
    {
      totalTasks = allTasks.size();
      openTasks = openCount;
      assignedTasks = assignedCount;
      completedTasks = completedCount;
      totalReward = totalReward;
      averageReward = avgReward;
    }
  };
};