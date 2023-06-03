// const proposalId = args[0];

// console.log("proposalId:", proposalId);

// const gptURL = "https://freelanco-backend.onrender.com/proposal/gptResponse?proposalId="

// console.log(`Sending HTTP request to ${gptURL}${proposalId}`)

// const gptRequest = Functions.makeHttpRequest({
// url: `${gptURL}${proposalId}`,
// method: "GET",
// })

// // Execute the API request (Promise)
// const gptResponse = await gptRequest

// if (gptResponse.error) {
// console.error(gptResponse.error)
// throw Error("Request failed, try checking the params provided")
// }

// console.log(gptResponse)

return Functions.encodeUint256(1);
