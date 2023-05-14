// const prompt = args[0];

// if (!secrets.openaiKey) {
//   throw Error("Need to set OPENAI_KEY environment variable");
// }

// const openAIRequest = Functions.makeHttpRequest({
//   url: "https://api.openai.com/v1/completions",
//   method: "POST",
//   headers: {
//     Authorization: `Bearer ${secrets.openaiKey}`,
//   },
//   data: {
//     model: "curie:ft-personal-2023-05-13-23-00-29",
//     prompt: prompt,
//     temperature: 1,
//     max_tokens: 2,
//   },
// });

// const [openAiResponse] = await Promise.all([openAIRequest]);
// console.log("raw response", openAiResponse);

// const result = openAiResponse.data.choices[0].text;
// if (result.includes("client")) {
//   return Functions.encodeUint256(0);
// } else {
//   return Functions.encodeUint256(1);
// }

return Functions.encodeUint256(1);
