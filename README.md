DynamicGens
===========

**DynamicGens** is a Stacks smart contract (`DynamicGens.clar`) designed for creating and managing a collection of **dynamic, generative Non-Fungible Tokens (NFTs)**. Unlike traditional static NFTs, each token in this collection is algorithmically generated at mint time and can continue to evolve or produce offspring through **evolution** and **breeding mechanics**. The contract introduces a rarity system that adapts as NFTs evolve across generations.

* * * * *

✨ Features
----------

-   **Algorithmic Trait Generation**\
    Unique traits are generated using a pseudo-random seed derived from block data, token ID, and user-specific inputs. This ensures every NFT is unique and unpredictable.

-   **Trait Evolution**\
    NFT owners can evolve their tokens. Evolution mutates traits, increases rarity scores, and advances NFTs to higher generations. Evolutions are gated by a cooldown period (`144` blocks) and capped by a maximum generation (`5`).

-   **Breeding Mechanics**\
    Two NFTs can breed to create a new offspring. Offspring inherit traits from both parents with pseudo-randomized variations, starting at a generation one higher than the highest parent.

-   **Dynamic Rarity System**\
    Rarity scores combine base trait rarity with generation multipliers, making evolved and bred NFTs progressively more rare and valuable.

-   **Owner-Controlled Functions**\
    Administrative safeguards allow the contract owner to pause the contract or disable evolution/breeding in case of bugs or misuse.

-   **SIP-009 Compliant Transfers**\
    The contract includes a `transfer` function compatible with the Stacks SIP-009 NFT standard, ensuring ecosystem interoperability.

* * * * *

⚙️ Contract Overview
--------------------

### Constants

-   **`contract-owner`** → Address with administrative privileges.

-   **`collection-limit`** → Max supply: `10,000` NFTs.

-   **`mint-price`** → `1 STX` (`u1000000` microSTX).

-   **`evolution-price`** → `0.5 STX` (`u500000` microSTX).

-   **`breeding-price`** → `2 STX` (`u2000000` microSTX).

-   **`evolution-cooldown-blocks`** → `144` blocks (~24 hours).

-   **`max-generation`** → `5`.

### Data Maps

-   **`nft-traits`** → Trait values, rarity score, generation, and lineage.

-   **`token-uris`** → Token metadata URIs.

-   **`token-owners`** → Tracks ownership of tokens.

-   **`owned-tokens`** → Up to 50 owned tokens per user.

-   **`evolution-history`** → Block heights of NFT evolutions (up to 10 entries).

-   **`last-evolution-block`** → Tracks cooldown for each NFT.

-   **`breeding-pairs`** → Records offspring of specific parent pairs.

### Private Functions

-   **`(generate-random-seed)`** → Produces a pseudo-random value based on user + token + block inputs.

-   **`(create-token-uri)`** → Safely builds metadata URI from base URI and token ID.

-   **`(calculate-rarity-score)`** → Computes rarity score (traits + generation multiplier).

-   **`(validate-traits)`** → Ensures trait values fall within valid ranges.

-   **`(add-token-to-owner)`** → Updates the list of tokens for a given principal.

-   **`(evolve-traits)`** → Produces mutated trait sets during evolution.

-   **`(breed-traits)`** → Inherits traits from two parents, introducing variation.

### Public Functions

-   **`mint-dynamic-nft(recipient)`** → Mints a new first-generation NFT.

-   **`evolve-nft(token-id)`** → Evolves an owned NFT, applying mutations and increasing generation.

-   **`breed-nfts(parent-one-id, parent-two-id, recipient)`** → Breeds two NFTs into a new offspring.

-   **`transfer(token-id, sender, recipient)`** → Transfers ownership per SIP-009.

-   **`toggle-contract-pause()`** → Pauses/unpauses minting, breeding, and evolution.

-   **`toggle-evolution()`** → Enables/disables evolution.

-   **`toggle-breeding()`** → Enables/disables breeding.

### Read-Only Functions

-   **`get-last-token-id()`** → Returns most recent token ID.

-   **`get-token-uri(token-id)`** → Fetches token metadata URI.

-   **`get-owner(token-id)`** → Returns token owner.

-   **`get-nft-traits(token-id)`** → Retrieves NFT's trait data.

-   **`get-contract-stats()`** → Provides overall collection stats.

-   **`get-evolution-history(token-id)`** → Lists block heights of evolutions.

-   **`can-evolve(token-id)`** → Checks cooldown eligibility for evolution.

* * * * *

🔒 Security Considerations
--------------------------

-   **Payments:** All mint, evolve, and breed functions enforce STX payments at fixed rates.

-   **Cooldown Enforcement:** Evolutions require a `144-block` cooldown to prevent rapid abuse.

-   **Generational Cap:** Prevents infinite scaling by capping generations at 5.

-   **Admin Control:** Owner-only toggles for pausing or disabling features act as fail-safes.

-   **Trait List Bounds:** Owned token lists and evolution histories are bounded to avoid overflows.

* * * * *

🚀 Deployment
-------------

1.  Clone the repository.

2.  Install [Clarinet](https://github.com/hirosystems/clarinet) for local development.

3.  Run `clarinet console` to interact with the contract locally.

4.  Deploy to Stacks testnet or mainnet using the Stacks CLI.

* * * * *

🧪 Testing
----------

This project uses **Clarinet** for contract testing.

```
clarinet test

```

Unit tests cover minting, trait validation, evolution cooldowns, breeding logic, and transfer compliance.

* * * * *

📊 Example Usage
----------------

```
;; Mint a new NFT
(mint-dynamic-nft tx-sender)

;; Evolve an NFT
(evolve-nft u1)

;; Breed NFTs #1 and #2 into a new NFT for the sender
(breed-nfts u1 u2 tx-sender)

;; Transfer NFT #1 to another user
(transfer u1 tx-sender 'SPXXXX...)

```

* * * * *

📜 License
----------

This project is licensed under the [MIT License](https://opensource.org/licenses/MIT).

* * * * *

🤝 Contributions
----------------

Contributions are welcome!\
Please open an issue or submit a pull request if you discover bugs, security concerns, or ideas for enhancements.

* * * * *

👤 Author
---------

Developed by **Akinseinde Ebenezer**.\
Profile picture:

![profile picture](https://lh3.googleusercontent.com/a/ACg8ocJ_vsw7TaCCeMuQ9lczLCzqs47IOD2H_aUfBxy6CgG3iFhEGtMA=s64-c)

* * * * *
