// ============================================
// FILE: src/canisters/UserCanister.mo
// Manages user profiles, reputation, and authentication
// ============================================

import Principal "mo:base/Principal";
import HashMap "mo:base/HashMap";
import Hash "mo:base/Hash";
import Iter "mo:base/Iter";
import Time "mo:base/Time";
import Nat "mo:base/Nat";
import Int "mo:base/Int";
import Float "mo:base/Float";
import Result "mo:base/Result";
import Array "mo:base/Array";
import Order "mo:base/Order";
import Buffer "mo:base/Buffer";
import Option "mo:base/Option";
import Text "mo:base/Text";

actor UserCanister {
  
  type UserId = Principal;
  
  public type UserRole = {
    #Worker;
    #TaskCreator;
    #Both;
    #Admin;
  };
  
  public type UserProfile = {
    id: UserId;
    username: Text;
    email: Text;
    role: UserRole;
    registeredAt: Time.Time;
    reputation: Int;
    totalEarned: Nat;
    totalSpent: Nat;
    completedTasks: Nat;
    createdTasks: Nat;
    bio: ?Text;
    skills: [Text];
    verified: Bool;
    active: Bool;
    avatarUrl: ?Text;
    languagePreferences: [Text];
  };
  
  public type UserStats = {
    successRate: Float;
    averageRating: Float;
    averageCompletionTime: Nat;
    totalRatings: Nat;
    lastActive: Time.Time;
    tasksThisWeek: Nat;
    tasksThisMonth: Nat;
  };
  
  public type Badge = {
    name: Text;
    description: Text;
    earnedAt: Time.Time;
    icon: Text;
  };
  
  public type ReputationChange = {
    userId: UserId;
    amount: Int;
    reason: Text;
    timestamp: Time.Time;
    taskId: ?Nat;
  };
  
  // Stable storage
  private stable var userEntries : [(UserId, UserProfile)] = [];
  private var users = HashMap.HashMap<UserId, UserProfile>(100, Principal.equal, Principal.hash);
  
  private stable var statsEntries : [(UserId, UserStats)] = [];
  private var userStats = HashMap.HashMap<UserId, UserStats>(100, Principal.equal, Principal.hash);
  
  private stable var badgesEntries : [(UserId, [Badge])] = [];
  private var userBadges = HashMap.HashMap<UserId, [Badge]>(100, Principal.equal, Principal.hash);
  
  private stable var usernameToIdEntries : [(Text, UserId)] = [];
  private var usernameToId = HashMap.HashMap<Text, UserId>(100, Text.equal, Text.hash);
  
  private stable var reputationHistoryEntries : [(UserId, [ReputationChange])] = [];
  private var reputationHistory = HashMap.HashMap<UserId, [ReputationChange]>(100, Principal.equal, Principal.hash);
  
  // Upgrade hooks
  system func preupgrade() {
    userEntries := Iter.toArray(users.entries());
    statsEntries := Iter.toArray(userStats.entries());
    badgesEntries := Iter.toArray(userBadges.entries());
    usernameToIdEntries := Iter.toArray(usernameToId.entries());
    reputationHistoryEntries := Iter.toArray(reputationHistory.entries());
  };
  
  system func postupgrade() {
    users := HashMap.fromIter<UserId, UserProfile>(userEntries.vals(), 100, Principal.equal, Principal.hash);
    userStats := HashMap.fromIter<UserId, UserStats>(statsEntries.vals(), 100, Principal.equal, Principal.hash);
    userBadges := HashMap.fromIter<UserId, [Badge]>(badgesEntries.vals(), 100, Principal.equal, Principal.hash);
    usernameToId := HashMap.fromIter<Text, UserId>(usernameToIdEntries.vals(), 100, Text.equal, Text.hash);
    reputationHistory := HashMap.fromIter<UserId, [ReputationChange]>(reputationHistoryEntries.vals(), 100, Principal.equal, Principal.hash);
  };
  
  // Register new user
  public shared(msg) func registerUser(
    username: Text,
    email: Text,
    role: UserRole,
    skills: [Text],
    languagePreferences: [Text]
  ) : async Result.Result<UserProfile, Text> {
    let caller = msg.caller;
    
    if (Principal.isAnonymous(caller)) {
      return #err("Anonymous users cannot register");
    };
    
    if (Text.size(username) < 3 or Text.size(username) > 20) {
      return #err("Username must be between 3 and 20 characters");
    };
    
    switch(users.get(caller)) {
      case(?_) { #err("User already registered") };
      case(null) {
        switch(usernameToId.get(username)) {
          case(?_) { #err("Username already taken") };
          case(null) {
            let profile : UserProfile = {
              id = caller;
              username = username;
              email = email;
              role = role;
              registeredAt = Time.now();
              reputation = 100;
              totalEarned = 0;
              totalSpent = 0;
              completedTasks = 0;
              createdTasks = 0;
              bio = null;
              skills = skills;
              verified = false;
              active = true;
              avatarUrl = null;
              languagePreferences = languagePreferences;
            };
            
            let stats : UserStats = {
              successRate = 100.0;
              averageRating = 0.0;
              averageCompletionTime = 0;
              totalRatings = 0;
              lastActive = Time.now();
              tasksThisWeek = 0;
              tasksThisMonth = 0;
            };
            
            users.put(caller, profile);
            userStats.put(caller, stats);
            usernameToId.put(username, caller);
            userBadges.put(caller, []);
            reputationHistory.put(caller, []);
            
            #ok(profile)
          };
        };
      };
    };
  };
  
  // Get user profile
  public query func getProfile(userId: UserId) : async ?UserProfile {
    users.get(userId)
  };
  
  // Get current user's profile
  public shared(msg) func getMyProfile() : async ?UserProfile {
    users.get(msg.caller)
  };
  
  // Get profile by username
  public query func getProfileByUsername(username: Text) : async ?UserProfile {
    switch(usernameToId.get(username)) {
      case(?userId) { users.get(userId) };
      case(null) { null };
    };
  };
  
  // Update user profile
  public shared(msg) func updateProfile(
    bio: ?Text,
    skills: [Text],
    avatarUrl: ?Text,
    languagePreferences: [Text]
  ) : async Result.Result<UserProfile, Text> {
    let caller = msg.caller;
    
    switch(users.get(caller)) {
      case(?profile) {
        let updated = {
          profile with 
          bio = bio;
          skills = skills;
          avatarUrl = avatarUrl;
          languagePreferences = languagePreferences;
        };
        users.put(caller, updated);
        #ok(updated)
      };
      case(null) { #err("User not found") };
    };
  };
  
  // Update reputation with history tracking
  public func updateReputation(
    userId: UserId, 
    change: Int, 
    reason: Text,
    taskId: ?Nat
  ) : async Result.Result<Int, Text> {
    switch(users.get(userId)) {
      case(?profile) {
        let newRep = profile.reputation + change;
        let capped = if (newRep < 0) { 0 } else { newRep };
        
        let updated = { profile with reputation = capped };
        users.put(userId, updated);
        
        // Track reputation change
        let repChange : ReputationChange = {
          userId = userId;
          amount = change;
          reason = reason;
          timestamp = Time.now();
          taskId = taskId;
        };
        
        let history = switch(reputationHistory.get(userId)) {
          case(?h) { h };
          case(null) { [] };
        };
        reputationHistory.put(userId, Array.append(history, [repChange]));
        
        // Check and award badges
        await checkAndAwardBadges(userId, capped);
        
        #ok(capped)
      };
      case(null) { #err("User not found") };
    };
  };
  
  // Update user earnings
  public func updateEarnings(userId: UserId, amount: Nat) : async Result.Result<(), Text> {
    switch(users.get(userId)) {
      case(?profile) {
        let updated = {
          profile with 
          totalEarned = profile.totalEarned + amount;
          completedTasks = profile.completedTasks + 1;
        };
        users.put(userId, updated);
        
        // Update weekly/monthly task counters
        switch(userStats.get(userId)) {
          case(?stats) {
            let updatedStats = {
              stats with
              tasksThisWeek = stats.tasksThisWeek + 1;
              tasksThisMonth = stats.tasksThisMonth + 1;
            };
            userStats.put(userId, updatedStats);
          };
          case(null) {};
        };
        
        await checkAndAwardBadges(userId, profile.reputation);
        
        #ok()
      };
      case(null) { #err("User not found") };
    };
  };
  
  // Update user spending
  public func updateSpending(userId: UserId, amount: Nat) : async Result.Result<(), Text> {
    switch(users.get(userId)) {
      case(?profile) {
        let updated = {
          profile with 
          totalSpent = profile.totalSpent + amount;
          createdTasks = profile.createdTasks + 1;
        };
        users.put(userId, updated);
        #ok()
      };
      case(null) { #err("User not found") };
    };
  };
  
  // Update user statistics
  public func updateStats(
    userId: UserId,
    rating: ?Float,
    completionTime: ?Nat,
    success: Bool
  ) : async Result.Result<(), Text> {
    switch(userStats.get(userId)) {
      case(?stats) {
        var newAvgRating = stats.averageRating;
        var newTotalRatings = stats.totalRatings;
        
        switch(rating) {
          case(?r) {
            if (r < 1.0 or r > 5.0) {
              return #err("Rating must be between 1 and 5");
            };
            newAvgRating := ((stats.averageRating * Float.fromInt(stats.totalRatings)) + r) / 
                           Float.fromInt(stats.totalRatings + 1);
            newTotalRatings := stats.totalRatings + 1;
          };
          case(null) {};
        };
        
        var newAvgTime = stats.averageCompletionTime;
        switch(completionTime) {
          case(?ct) {
            if (stats.averageCompletionTime == 0) {
              newAvgTime := ct;
            } else {
              newAvgTime := (stats.averageCompletionTime + ct) / 2;
            };
          };
          case(null) {};
        };
        
        let updated = {
          stats with
          averageRating = newAvgRating;
          averageCompletionTime = newAvgTime;
          totalRatings = newTotalRatings;
          lastActive = Time.now();
        };
        
        userStats.put(userId, updated);
        #ok()
      };
      case(null) { #err("User stats not found") };
    };
  };
  
  // Get user statistics
  public query func getUserStats(userId: UserId) : async ?UserStats {
    userStats.get(userId)
  };
  
  // Get user badges
  public query func getUserBadges(userId: UserId) : async [Badge] {
    switch(userBadges.get(userId)) {
      case(?badges) { badges };
      case(null) { [] };
    };
  };
  
  // Get reputation history
  public query func getReputationHistory(userId: UserId, limit: Nat) : async [ReputationChange] {
    switch(reputationHistory.get(userId)) {
      case(?history) {
        let sorted = Array.sort(history, func(a: ReputationChange, b: ReputationChange) : Order.Order {
          if (a.timestamp > b.timestamp) { #less }
          else if (a.timestamp < b.timestamp) { #greater }
          else { #equal }
        });
        let actualLimit = if (sorted.size() < limit) { sorted.size() } else { limit };
        Array.tabulate<ReputationChange>(actualLimit, func(i) { sorted[i] })
      };
      case(null) { [] };
    };
  };
  
  // Check and award badges
  private func checkAndAwardBadges(userId: UserId, reputation: Int) : async () {
    switch(users.get(userId)) {
      case(?profile) {
        let currentBadges = switch(userBadges.get(userId)) {
          case(?b) { b };
          case(null) { [] };
        };
        
        let buf = Buffer.Buffer<Badge>(currentBadges.size() + 10);
        for (badge in currentBadges.vals()) {
          buf.add(badge);
        };
        
        // First task badge
        if (profile.completedTasks == 1 and not hasBadge(currentBadges, "First Steps")) {
          buf.add({
            name = "First Steps";
            description = "Completed your first task";
            earnedAt = Time.now();
            icon = "🎯";
          });
        };
        
        // 10 tasks badge
        if (profile.completedTasks >= 10 and not hasBadge(currentBadges, "Getting Started")) {
          buf.add({
            name = "Getting Started";
            description = "Completed 10 tasks";
            earnedAt = Time.now();
            icon = "🌟";
          });
        };
        
        // 50 tasks badge
        if (profile.completedTasks >= 50 and not hasBadge(currentBadges, "Professional")) {
          buf.add({
            name = "Professional";
            description = "Completed 50 tasks";
            earnedAt = Time.now();
            icon = "💼";
          });
        };
        
        // 100 tasks badge
        if (profile.completedTasks >= 100 and not hasBadge(currentBadges, "Centurion")) {
          buf.add({
            name = "Centurion";
            description = "Completed 100 tasks";
            earnedAt = Time.now();
            icon = "💯";
          });
        };
        
        // 500 tasks badge
        if (profile.completedTasks >= 500 and not hasBadge(currentBadges, "Master")) {
          buf.add({
            name = "Master";
            description = "Completed 500 tasks";
            earnedAt = Time.now();
            icon = "👑";
          });
        };
        
        // Reputation badges
        if (reputation >= 250 and not hasBadge(currentBadges, "Trusted")) {
          buf.add({
            name = "Trusted";
            description = "Reached 250 reputation";
            earnedAt = Time.now();
            icon = "⭐";
          });
        };
        
        if (reputation >= 500 and not hasBadge(currentBadges, "Highly Trusted")) {
          buf.add({
            name = "Highly Trusted";
            description = "Reached 500 reputation";
            earnedAt = Time.now();
            icon = "🌟";
          });
        };
        
        if (reputation >= 1000 and not hasBadge(currentBadges, "Elite")) {
          buf.add({
            name = "Elite";
            description = "Reached 1000 reputation";
            earnedAt = Time.now();
            icon = "💎";
          });
        };
        
        // Earning badges (in satoshis)
        if (profile.totalEarned >= 100000 and not hasBadge(currentBadges, "First 100K")) {
          buf.add({
            name = "First 100K";
            description = "Earned 100,000 satoshis";
            earnedAt = Time.now();
            icon = "💰";
          });
        };
        
        if (profile.totalEarned >= 1000000 and not hasBadge(currentBadges, "Millionaire")) {
          buf.add({
            name = "Millionaire";
            description = "Earned 1,000,000 satoshis";
            earnedAt = Time.now();
            icon = "🏆";
          });
        };
        
        if (profile.totalEarned >= 10000000 and not hasBadge(currentBadges, "Bitcoin Baron")) {
          buf.add({
            name = "Bitcoin Baron";
            description = "Earned 10,000,000 satoshis";
            earnedAt = Time.now();
            icon = "👑";
          });
        };
        
        userBadges.put(userId, Buffer.toArray(buf));
      };
      case(null) {};
    };
  };
  
  // Helper: Check if user has a badge
  private func hasBadge(badges: [Badge], name: Text) : Bool {
    for (badge in badges.vals()) {
      if (badge.name == name) {
        return true;
      };
    };
    false
  };
  
  // Get leaderboard
  public query func getLeaderboard(limit: Nat) : async [UserProfile] {
    let allUsers = Iter.toArray(users.vals());
    let activeUsers = Array.filter<UserProfile>(allUsers, func(user) { user.active });
    let sorted = Array.sort(activeUsers, func(a: UserProfile, b: UserProfile) : Order.Order {
      if (a.reputation > b.reputation) { #less }
      else if (a.reputation < b.reputation) { #greater }
      else { #equal }
    });
    
    let actualLimit = if (sorted.size() < limit) { sorted.size() } else { limit };
    Array.tabulate<UserProfile>(actualLimit, func(i) { sorted[i] })
  };
  
  // Get top earners leaderboard
  public query func getTopEarners(limit: Nat) : async [UserProfile] {
    let allUsers = Iter.toArray(users.vals());
    let sorted = Array.sort(allUsers, func(a: UserProfile, b: UserProfile) : Order.Order {
      if (a.totalEarned > b.totalEarned) { #less }
      else if (a.totalEarned < b.totalEarned) { #greater }
      else { #equal }
    });
    
    let actualLimit = if (sorted.size() < limit) { sorted.size() } else { limit };
    Array.tabulate<UserProfile>(actualLimit, func(i) { sorted[i] })
  };
  
  // Search users
  public query func searchUsers(query: Text, limit: Nat) : async [UserProfile] {
    let allUsers = Iter.toArray(users.vals());
    let lowerQuery = Text.toLowercase(query);
    
    let filtered = Array.filter<UserProfile>(allUsers, func(user) {
      let lowerUsername = Text.toLowercase(user.username);
      Text.contains(lowerUsername, #text lowerQuery) or
      Array.find<Text>(user.skills, func(skill) {
        Text.contains(Text.toLowercase(skill), #text lowerQuery)
      }) != null
    });
    
    let actualLimit = if (filtered.size() < limit) { filtered.size() } else { limit };
    Array.tabulate<UserProfile>(actualLimit, func(i) { filtered[i] })
  };
  
  // Verify user (admin only)
  public shared(msg) func verifyUser(userId: UserId) : async Result.Result<(), Text> {
    // In production, check if caller is admin
    switch(users.get(userId)) {
      case(?profile) {
        let updated = { profile with verified = true };
        users.put(userId, updated);
        #ok()
      };
      case(null) { #err("User not found") };
    };
  };
  
  // Deactivate user account
  public shared(msg) func deactivateAccount() : async Result.Result<(), Text> {
    let caller = msg.caller;
    
    switch(users.get(caller)) {
      case(?profile) {
        let updated = { profile with active = false };
        users.put(caller, updated);
        #ok()
      };
      case(null) { #err("User not found") };
    };
  };
  
  // Get platform statistics
  public query func getPlatformStats() : async {
    totalUsers: Nat;
    activeUsers: Nat;
    totalTasksCompleted: Nat;
    totalEarnings: Nat;
  } {
    let allUsers = Iter.toArray(users.vals());
    var activeCount = 0;
    var totalTasks = 0;
    var totalEarnings = 0;
    
    for (user in allUsers.vals()) {
      if (user.active) { activeCount += 1 };
      totalTasks += user.completedTasks;
      totalEarnings += user.totalEarned;
    };
    
    {
      totalUsers = allUsers.size();
      activeUsers = activeCount;
      totalTasksCompleted = totalTasks;
      totalEarnings = totalEarnings;
    }
  };
};