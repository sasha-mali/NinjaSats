# NinjaSats - Freelance Microtasks Platform
Encode ICP Hackathon 

A decentralized freelance microtask platform built on the Internet Computer, enabling quick jobs (surveys, data labeling, feedback) with instant payments in satoshis.

## 🏗️ Architecture

NinjaSats uses a multi-canister architecture for scalability and separation of concerns:

### Canisters

1. **UserCanister** - User management, profiles, reputation, and badges
2. **TaskCanister** - Task creation, assignment, submission, and reviews
3. **PaymentCanister** - Satoshi payments, escrow, and transaction management
4. **DisputeCanister** - Dispute creation, resolution, and evidence management
5. **CoordinatorCanister** - Orchestrates workflows across all canisters

## 📁 Project Structure

```
ninjasats/
├── src/
│   ├── types/
│   │   └── Types.mo              # Shared type definitions
│   └── canisters/
│       ├── UserCanister.mo       # User management
│       ├── TaskCanister.mo       # Task operations
│       ├── PaymentCanister.mo    # Payment & escrow
│       ├── DisputeCanister.mo    # Dispute resolution
│       └── CoordinatorCanister.mo # Workflow orchestration
├── dfx.json                      # DFX configuration
└── README.md                     # This file
```

## 🚀 Getting Started

### Prerequisites

- [DFINITY Canister SDK](https://internetcomputer.org/docs/current/developer-docs/setup/install/) (dfx)
- Node.js 16+ (for frontend development)
- Vessel (Motoko package manager) - optional

### Installation

1. **Clone the repository**
```bash
git clone https://github.com/yourusername/ninjasats.git
cd ninjasats
```

2. **Start the local Internet Computer replica**
```bash
dfx start --clean --background
```

3. **Deploy the canisters**
```bash
# Deploy all canisters
dfx deploy

# Or deploy individually
dfx deploy ninjasats_user
dfx deploy ninjasats_task
dfx deploy ninjasats_payment
dfx deploy ninjasats_dispute
dfx deploy ninjasats_coordinator
```

4. **Initialize the coordinator with canister IDs**
```bash
dfx canister call ninjasats_coordinator initializeCanisters '(
  "USER_CANISTER_ID",
  "TASK_CANISTER_ID", 
  "PAYMENT_CANISTER_ID",
  "DISPUTE_CANISTER_ID"
)'
```

## 📖 Usage Examples

### User Registration

```bash
dfx canister call ninjasats_user registerUser '(
  "ninja_warrior",
  "warrior@ninjasats.com",
  variant { Both },
  vec { "Data Labeling"; "Surveys"; "Feedback" },
  vec { "English"; "Spanish" }
)'
```

### Create a Task

```bash
dfx canister call ninjasats_task createTask '(
  "Label 100 Images",
  "Label images of cats and dogs for ML training",
  "Please accurately identify whether each image contains a cat or dog",
  variant { DataLabeling },
  variant { Medium },
  50000,
  vec { "Data Labeling" },
  30,
  null,
  1,
  vec { "machine-learning"; "images" },
  vec {}
)'
```

### Deposit Satoshis

```bash
dfx canister call ninjasats_payment deposit '(
  principal "USER_PRINCIPAL",
  100000,
  "bitcoin_tx_hash_here"
)'
```

### Lock Escrow for Task

```bash
dfx canister call ninjasats_payment lockEscrow '(
  0,
  50000,
  null
)'
```

### Accept a Task

```bash
dfx canister call ninjasats_task assignTask '(0)'
```

### Submit Task

```bash
dfx canister call ninjasats_task submitTask '(
  0,
  "https://drive.google.com/submission",
  opt "Completed all 100 labels",
  vec {}
)'
```

### Approve Task & Release Payment

```bash
dfx canister call ninjasats_coordinator approveTaskWorkflow '(
  0,
  5,
  opt "Excellent work!"
)'
```

## 🔥 Key Features

### User Management
- ✅ User registration with roles (Worker, TaskCreator, Both, Admin)
- ✅ Profile management with skills and preferences
- ✅ Reputation system with history tracking
- ✅ Badge system for achievements
- ✅ Leaderboards (reputation, earnings)
- ✅ User search and discovery

### Task Management
- ✅ Multiple task types (Survey, DataLabeling, Feedback, etc.)
- ✅ Difficulty levels (Easy, Medium, Hard)
- ✅ Task filtering by type, difficulty, reward, skills
- ✅ Task assignment and status tracking
- ✅ Submission with attachments
- ✅ Review and rating system (1-5 stars)
- ✅ Task cancellation and unassignment

### Payment System
- ✅ Satoshi balance management
- ✅ Escrow system for secure payments
- ✅ Instant payment release on approval
- ✅ Platform fee system (configurable)
- ✅ Transaction history
- ✅ Withdrawal requests to Bitcoin addresses
- ✅ Bonus/tip system

### Dispute Resolution
- ✅ Dispute creation with evidence
- ✅ Messaging between parties
- ✅ Evidence submission
- ✅ Multiple resolution types (favor creator, favor worker, split)
- ✅ Dispute status tracking
- ✅ Resolution statistics

### Coordinator Workflows
- ✅ Complete task creation workflow (create + escrow)
- ✅ Task approval workflow (review + payment + reputation)
- ✅ Task rejection workflow (review + dispute/refund)
- ✅ Dashboard aggregation
- ✅ Platform statistics

## 💰 Payment Flow

```
1. Creator deposits satoshis → Balance
2. Creator creates task → Escrow locks funds
3. Worker accepts & completes task
4. Worker submits task
5. Creator reviews:
   ✅ Approved → Escrow releases to worker (minus platform fee)
   ❌ Rejected → Dispute or refund to creator
```

## 🎯 Reputation System

Reputation changes based on task outcomes:
- ⭐⭐⭐⭐⭐ (5 stars): +15 reputation
- ⭐⭐⭐⭐ (4 stars): +10 reputation
- ⭐⭐⭐ (3 stars): +5 reputation
- ⭐⭐ (2 stars): +0 reputation
- ⭐ (1 star): -5 reputation
- Task rejection: -10 reputation
- Task cancellation after assignment: -5 reputation

## 🏆 Badge System

Users earn badges for achievements:
- **First Steps**: Complete 1 task
- **Getting Started**: Complete 10 tasks
- **Professional**: Complete 50 tasks
- **Centurion**: Complete 100 tasks
- **Master**: Complete 500 tasks
- **Trusted**: Reach 250 reputation
- **Highly Trusted**: Reach 500 reputation
- **Elite**: Reach 1000 reputation
- **First 100K**: Earn 100,000 satoshis
- **Millionaire**: Earn 1,000,000 satoshis
- **Bitcoin Baron**: Earn 10,000,000 satoshis

## 🔧 Configuration

### Platform Fee
Default: 5% (configurable by admin)

```bash
dfx canister call ninjasats_payment updatePlatformFee '(3)'
```

### Minimum Values
- Minimum task reward: 100 satoshis
- Minimum deposit: 1,000 satoshis
- Minimum withdrawal: 10,000 satoshis

## 🧪 Testing

```bash
# Run Motoko tests (if configured)
dfx test

# Test individual canister methods
dfx canister call ninjasats_user getPlatformStats
dfx canister call ninjasats_task getTaskStats
dfx canister call ninjasats_payment getPaymentStats
dfx canister call ninjasats_dispute getDisputeStats
```

## 📊 Query Methods

### Get User Info
```bash
dfx canister call ninjasats_user getProfile '(principal "USER_ID")'
dfx canister call ninjasats_user getUserStats '(principal "USER_ID")'
dfx canister call ninjasats_user getUserBadges '(principal "USER_ID")'
```

### Get Task Info
```bash
dfx canister call ninjasats_task getTask '(0)'
dfx canister call ninjasats_task getAvailableTasks '(null, 10, 0)'
```

### Get Payment Info
```bash
dfx canister call ninjasats_payment getBalance '(principal "USER_ID")'
dfx canister call ninjasats_payment getTransactionHistory '(principal "USER_ID", 10, 0)'
```

## 🔐 Security Considerations

1. **Escrow Protection**: Funds are locked in escrow until task completion
2. **Anonymous Prevention**: Anonymous principals cannot perform sensitive operations
3. **Authorization Checks**: Only authorized users can perform actions (creator reviews, worker submits)
4. **Dispute System**: Protects both parties in case of disagreements
5. **Reputation System**: Prevents abuse through reputation tracking

## 🚧 Future Enhancements

- [ ] Integration with Bitcoin Lightning Network for faster payments
- [ ] Multi-signature escrow for high-value tasks
- [ ] AI-powered task matching based on skills
- [ ] Automated dispute resolution using ML
- [ ] Mobile app (iOS/Android)
- [ ] Browser extension for quick task access
- [ ] API for third-party integrations
- [ ] Advanced analytics dashboard
- [ ] Team/organization accounts
- [ ] Recurring tasks and subscriptions

## 🤝 Contributing

Contributions are welcome! Please follow these steps:

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## 📝 License

This project is licensed under the MIT License - see the LICENSE file for details.

## 🙋 Support

- Documentation: [docs.ninjasats.com](https://docs.ninjasats.com)
- Discord: [discord.gg/ninjasats](https://discord.gg/ninjasats)
- Twitter: [@NinjaSats](https://twitter.com/ninjasats)
- Email: support@ninjasats.com

## 🎉 Acknowledgments

- Built on the [Internet Computer](https://internetcomputer.org/)
- Inspired by platforms like Amazon MTurk, Fiverr, and Upwork
- Bitcoin integration for decentralized payments

---

**Made with ⚡ by the NinjaSats Team**