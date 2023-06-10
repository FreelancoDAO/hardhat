const proposalId = args[0];

console.log("proposalId:", proposalId);

const gptURL = "https://free-yk04.onrender.com/proposal/gptResponse";

console.log(`Sending HTTP request to ${gptURL} for ${proposalId}`);

const gptRequest = Functions.makeHttpRequest({
  url: `${gptURL}`,
  method: "POST",
  data: {
    proposalId: proposalId,
  },
});

// Execute the API request (Promise)
const gptResponse = await gptRequest;

if (gptResponse.error) {
  console.error(gptResponse.error);
  throw Error("Request failed, try checking the params provided");
}

return Functions.encodeUint256(gptResponse.data.result);
