<div align="center">
    <img src="https://pbs.twimg.com/profile_images/1653232294151475200/FyoHlx_s_400x400.jpg" alt="Lenster Logo" height="100" width="100">
    <h1>FreelancoDAO</h1>
    <strong>Decentralized, and permissionless freelance platform 🌿</strong>
</div>
<br>
<div align="center">
    <div>
    
        <img src="https://img.shields.io/badge/chainlink-375BD2?style=for-the-badge&logo=chainlink&logoColor=white" alt="Lens">
    
    
        <img src="https://img.shields.io/badge/Ethereum-3C3C3D?style=for-the-badge&logo=Ethereum&logoColor=white" alt="Vercel">
    
    
        <img src="https://img.shields.io/badge/OpenZeppelin-4E5EE4?logo=OpenZeppelin&logoColor=fff&style=for-the-badge" alt="Vercel">
    
    </div>
    <a href="https://deepsource.io/gh/FreelancoDAO/hardhat">
        <img src="https://public-api.gitpoap.io/v1/repo/FreelancoDAO/hardhat/badge" alt="Gitpoap">
    </a>
    <a href="https://github.com/FreelancoDAO/hardhat/stargazers">
        <img src="https://img.shields.io/github/stars/FreelancoDAO/hardhat?label=Stars&logo=github" alt="Stargazers">
    </a>
    <a href="https://github.com/FreelancoDAO/hardhat/blob/main/LICENSE">
        <img src="https://img.shields.io/github/license/FreelancoDAO/hardhat?label=Licence&logo=gnu" alt="License">
    </a>
    <a href="https://github.com/FreelancoDAO/hardhat">
        <img src="https://img.shields.io/github/issues/FreelancoDAO/hardhat/Bounty?color=8b5cf6&label=Bounties&logo=ethereum" alt="Bounties">
    </a>
</div>
<div align="center">
    <br>
    <a href="https://freelanco.in"><b> www.freelanco.in »</b></a>
    <br><br>
    <a href="https://discord.gg/4uwzgkEp"><b>Discord</b></a>
    •
    <a href="https://github.com/FreelancoDAO/hardhat/issues/new"><b>Issues</b></a>
</div>
<br />

<a href="https://github.com/FreelancoDAO/hardhat/graphs/contributors">
  <img src="https://contrib.rocks/image?repo=FreelancoDAO/hardhat" />
</a>

## About FreelancoDAO

FreelancoDAO, is a community driven freelancer platform, where members of the DAO vote to make a decision on a dispute on the platform to act as an arbitrator. The FreelancoDAO does one thing: it replaces third-party trust with mathematical proof that something happened. By providing a decentralized and automated dispute resolution platform, FreelancoDAO offer a unique value proposition that addresses a significant problem in the industry i.e CENSORSHIP. 

## GPT Voting

By providing a decentralized autonomous organization for freelancers and clients, FreelancoDAO offers a fair and transparent voting mechanism for conflict resolution. Members of the FreelancoDAO can review conversational evidence and documents to facilitate a fair agreement to resolve disputes in favor of the client or the freelancer. This voting mechanism is supplemented with a state-of-the-art automated AI model, which independently reviews the provided evidence to decide how to resolve the conflict. The model's decision is considered in tandem with the popular vote results to decide which party is ultimately in favor, thereby negating any bias or collusion among the members of the DAO. The use of AI technology ensures that at least one vote is constantly cast, even in the absence of members, providing a fast and reliable conflict resolution mechanism for freelancers and clients alike.

<div id="top"></div>


- [Getting Started](#getting-started)
  - [Requirements](#requirements)
    - [Installation](#installation)
  - [Usage](#usage)
  - [Roadmap](#roadmap)
  - [Contributing](#contributing)
  - [License](#license)
  - [Contact](#contact)
  - [Acknowledgments](#acknowledgments)

<!-- GETTING STARTED -->
# Getting Started 

Work with this repo in the browser (optional)<br/>

[![Open in Gitpod](https://gitpod.io/button/open-in-gitpod.svg)](https://gitpod.io/#https://github.com/FreelancoDAO/hardhat)

## Requirements

- [git](https://git-scm.com/book/en/v2/Getting-Started-Installing-Git)
  - You'll know you did it right if you can run `git --version` and you see a response like `git version x.x.x`
- [Nodejs](https://nodejs.org/en/)
  - You'll know you've installed nodejs right if you can run:
    - `node --version`and get an ouput like: `vx.x.x`
- [Yarn](https://classic.yarnpkg.com/lang/en/docs/install/) instead of `npm`
  - You'll know you've installed yarn right if you can run:
    - `yarn --version` And get an output like: `x.x.x`
    - You might need to install it with npm

### Installation

1. Clone this repo:
```
git clone https://github.com/FreelancoDAO/hardhat.git
cd hardhat
```
2. Install dependencies
```sh
yarn
```

or 

```
npm i 
```

3. Run the test suite (which also has all the functionality)

```
yarn hardhat test
```
or
```
npx hardhat test
```


<!-- USAGE EXAMPLES -->
## Usage
### On-Chain Governance Example

Here is the rundown of what the test suite does. 

The code sets up various contract instances for a governance system, including:

🏛️ GovernorContract
💼 GovernanceToken
⏳ TimeLock
🕴️ Freelanco
🖼️ DaoNFT
🔑 DAOReputationToken
💼 GigNFT


The code initializes the contract instances and sets up the necessary fixtures before each test case.

The test cases:

1. 💬 Verifying that dispute resolution can only be done through governance.
2. 📜 Checking that granting can only be performed through governance.
3. 📩 Testing sending an offer to a non-existing Gig token ID.
4. ❌ Checking if sending an offer with less than 0 ETH value reverts the transaction.
5. 💰 Verifying that sending less than the mint fee when requesting an NFT reverts the transaction.
6. 🗳️ Ensuring that voting fails when a member doesn't have a DAO NFT.
7. 🔄 Simulating the entire flow of sending an offer, approving the offer, initiating a dispute, voting, and executing the proposal.
8. 🎁 Testing initiating a grant proposal, voting on the proposal, and executing it.


<!-- ROADMAP -->
## Roadmap

- [] Add Staking rewards for Escrow Transactions
- [] Add XMTP Protcol for messaging
- [] Add Lens Protocol for Profile NFTs

See the [open issues](https://github.com/FreelancoDAO/hardhat/issues) for a full list of proposed features (and known issues).

<!-- CONTRIBUTING -->
## ✅ Community

For a place to have open discussions on features, voice your ideas, or get help with general questions please visit our community at [Discord](https://discord.gg/4uwzgkEp).

## 💕 Contributors

We love contributors! Feel free to contribute to this project but please read the [Contributing Guidelines](CONTRIBUTING.md) before opening an issue or PR so you understand the branching strategy and local development environment.

Contributions are what make the open source community such an amazing place to learn, inspire, and create. Any contributions you make are **greatly appreciated**.

If you have a suggestion that would make this better, please fork the repo and create a pull request. You can also simply open an issue with the tag "enhancement".
Don't forget to give the project a star! Thanks again!

1. Fork the Project
2. Create your Feature Branch (`git checkout -b feature/AmazingFeature`)
3. Commit your Changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to the Branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request

<p align="right">(<a href="#top">back to top</a>)</p>

<!-- CONTACT -->
## Contact

Shivam Arora - [@Shivam017arora](https://twitter.com/Shivam017arora)

<p align="right">(<a href="#top">back to top</a>)</p>


<!-- ACKNOWLEDGMENTS -->
## Acknowledgments

* [Patrick Collins - Governance Walkthrough](https://www.youtube.com/watch?v=AhJtmUqhAqg)
* [Openzeppelin Governance Walkthrough](https://docs.openzeppelin.com/contracts/4.x/governance)
* [Openzeppelin Governance Github](https://github.com/OpenZeppelin/openzeppelin-contracts/tree/master/contracts/governance)
* [Vitalik on DAOs](https://blog.ethereum.org/2014/05/06/daos-dacs-das-and-more-an-incomplete-terminology-guide/)
* [Vitalik on On-Chain Governance](https://vitalik.ca/general/2021/08/16/voting3.html)
* [Vitalik on Governance in General](https://vitalik.ca/general/2017/12/17/voting.html)

<p align="right">(<a href="#top">back to top</a>)</p>


## License

FreelancoDAO is open-sourced software licensed under the © [GPLv3](LICENSE).
