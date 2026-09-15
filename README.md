# FTL (FinanceTrackerLite)

**An iOS app that learns to read your receipts. Gmail in, a Google Sheet out, everything in between on the device.**

FTL is a smart personal finance tracker that automatically captures spending from email receipts (via Gmail), categorizes transactions using on-device foundation models, and syncs the finalized data to your own Google Sheet.

## 🌟 The Design Principle

> The model acts autonomously only where false positives are **recoverable** (the provisional cache), and defers to tools where errors would be **invisible** (the math). Everything canonical is gated by a rule or by the user.

- **Human in the loop**: The model proposes (e.g., categorizing a new merchant, learning a new sender's receipt template), but **you** decide. 
- **No autonomous writes**: Nothing reaches your Google Sheet ledger without your approval in the queue.
- **Deterministic Math**: The model never does arithmetic. All calculations are handled deterministically or by Google Sheets formulas.

## 🏗 Architecture

FTL is built with a split **System / Agent** architecture:

* **System (Deterministic)**: 
  * Parses incoming receipts using learned patterns.
  * Deduplicates and pairs transactions.
  * Manages memory (tags and merchants you have previously confirmed).
  * Calculates budget totals.
* **Agent (Foundation Models)**:
  * Proposes tags/categories for new merchants with no history.
  * Synthesizes new parser rules offline when encountering a new email template.
  * _Never writes to the ledger, never does math, and never routes based on its own confidence._

### Tech Stack
* **Platform**: iOS (SwiftUI)
* **Local Storage**: SwiftData (Caching provisional entries, tag memory, etc.)
* **Backend / Ledger**: Google Sheets (Canonical data source)
* **Auth**: Google Sign-In (For Gmail access and Sheets sync)
* **Intelligence**: On-device Foundation Models

## 🚀 Getting Started

1. Open `FTL.xcodeproj` in Xcode.
2. Ensure you have the necessary Google API credentials configured (see `secrets.plist` if required).
3. The app supports a **Sample Mode** (fixtures) and a **Live Without Sheet** mode for local testing without modifying real ledgers. You can toggle these environments for development.

## 📚 Documentation

For an in-depth understanding of FTL's internals, roadmap, and design decisions, check the `docs/` directory:

- [CLAUDE.md](FTL/docs/CLAUDE.md) - Extensive development guide, architecture rules, and invariants.
- [one-pager.html](FTL/docs/one-pager.html) - High-level summary of the system boundary.
- [ROADMAP.md](FTL/docs/ROADMAP.md) - Project roadmap and feature audits.
- [TESTING.md](FTL/docs/TESTING.md) - Details on constraints and manual testing procedures.
- [AGENT_ENTRYPOINTS.md](FTL/docs/AGENT_ENTRYPOINTS.md) - Details on where AI models are used within the pipeline.
