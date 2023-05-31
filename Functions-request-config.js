const fs = require("fs");

// Loads environment variables from .env.enc file (if it exists)
require("@chainlink/env-enc").config();

const Location = {
  Inline: 0,
  Remote: 1,
};

const CodeLanguage = {
  JavaScript: 0,
};

const ReturnType = {
  uint: "uint256",
  uint256: "uint256",
  int: "int256",
  int256: "int256",
  string: "string",
  bytes: "Buffer",
  Buffer: "Buffer",
};

// Configure the request by setting the fields below
const requestConfig = {
  // Location of source code (only Inline is currently supported)
  codeLocation: Location.Inline,
  // Code language (only JavaScript is currently supported)
  codeLanguage: CodeLanguage.JavaScript,
  // String containing the source code to be executed
  source: fs.readFileSync("./API-request-example.js").toString(),
  //source: fs.readFileSync('./API-request-example.js').toString(),
  // Secrets can be accessed within the source code with `secrets.varName` (ie: secrets.apiKey). The secrets object can only contain string values.
  secrets: { openaiKey: process.env.OPEN_AI_API_KEY ?? "" },
  // Per-node secrets objects assigned to each DON member. When using per-node secrets, nodes can only use secrets which they have been assigned.
  perNodeSecrets: [],
  // ETH wallet key used to sign secrets so they cannot be accessed by a 3rd party
  walletPrivateKey: process.env["PRIVATE_KEY"],
  // Args (string only array) can be accessed within the source code with `args[index]` (ie: args[0]).
  args: [
    "Freelancer: Great! I will get started immediately. I will keep you updated throughout the process.(15 days later)Client: Hi, I haven't received the video animation yet. When will it be ready?Freelancer: Hi, I'm sorry for the delay. I've had some unexpected issues come up, but I'm working on it and should have it ready within the next couple of days.(Client waits for 2 more days)Client: Hi, it's been 17 days now and I still haven't received the video animation. Can you please update me on the progress?Freelancer: Hi, I'm sorry for the delay again. I'm facing some technical issues and I'm unable to deliver the video animation. I understand that I've missed the deadline but I will deliver the project as soon as possible.Client: This is unacceptable. You promised to deliver in 15 days and now it's been 17 days and you still haven't delivered. I cannot wait any longer. I need to raise a dispute.Freelancer: I understand your frustration, but I assure you that I am doing everything I can to resolve this issue. I apologize for the delay and I will work diligently to complete the project as soon as possible.(Client raises a dispute)\n\n###\n\n\nVote:",
    BigInt("15296962647124412230465376992725277514887943516153623806346778128378551958309"),
  ],
  // Expected type of the returned value
  expectedReturnType: ReturnType.string,
  // Redundant URLs which point to encrypted off-chain secrets
  secretsURLs: [],
};

module.exports = requestConfig;
