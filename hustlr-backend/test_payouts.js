require('dotenv').config({ path: './.env' });
const { initiateUpiPayout } = require('./src/services/instamojo_payout.js');

async function test() {
  console.log("--- Testing Instamojo Simulated Payments API ---");
  console.log("Loaded API Key:", process.env.INSTAMOJO_API_KEY ? "Present" : "Missing");
  
  const workerUpi = 'gigworker@ybl';
  const amountPaise = 50000; // Rs 500

  const result = await initiateUpiPayout(workerUpi, amountPaise);
  
  console.log("\nResult:");
  console.log(JSON.stringify(result, null, 2));
}

test();
