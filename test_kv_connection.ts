#!/usr/bin/env -S deno run --allow-net --allow-env

/**
 * Test script for remote KV connection
 * Server: 102.37.137.29:4512
 * Access token: d4f2332c86df1ec68911c73b51c9dbad
 */

const KV_URL = "http://102.37.137.29:4512";
const ACCESS_TOKEN = "d4f2332c86df1ec68911c73b51c9dbad";

async function testKVConnection() {
  console.log("🔗 Testing remote KV connection...");
  console.log(`📍 Server: ${KV_URL}`);
  console.log(`🔑 Token: ${ACCESS_TOKEN.substring(0, 8)}...`);
  console.log("");

  try {
    // Test 1: Basic connectivity
    console.log("1️⃣ Testing basic connectivity...");
    const response = await fetch(KV_URL, {
      method: "GET",
      headers: {
        "Authorization": `Bearer ${ACCESS_TOKEN}`,
        "Content-Type": "application/json",
      },
    });

    if (!response.ok) {
      throw new Error(`HTTP ${response.status}: ${response.statusText}`);
    }

    console.log("✅ Basic connectivity test passed");
    console.log(`   Status: ${response.status} ${response.statusText}`);
    console.log("");

    // Test 2: Set a test key-value pair
    console.log("2️⃣ Testing key-value operations...");
    const testKey = "test_key_" + Date.now();
    const testValue = "Hello from Deno!";

    const setResponse = await fetch(`${KV_URL}/kv/${testKey}`, {
      method: "PUT",
      headers: {
        "Authorization": `Bearer ${ACCESS_TOKEN}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ value: testValue }),
    });

    if (!setResponse.ok) {
      throw new Error(`Failed to set key: ${setResponse.status} ${setResponse.statusText}`);
    }

    console.log("✅ Key set successfully");
    console.log(`   Key: ${testKey}`);
    console.log(`   Value: ${testValue}`);
    console.log("");

    // Test 3: Get the test key-value pair
    console.log("3️⃣ Testing key retrieval...");
    const getResponse = await fetch(`${KV_URL}/kv/${testKey}`, {
      method: "GET",
      headers: {
        "Authorization": `Bearer ${ACCESS_TOKEN}`,
      },
    });

    if (!getResponse.ok) {
      throw new Error(`Failed to get key: ${getResponse.status} ${getResponse.statusText}`);
    }

    const retrievedData = await getResponse.json();
    console.log("✅ Key retrieved successfully");
    console.log(`   Retrieved value: ${retrievedData.value}`);
    console.log("");

    // Test 4: Verify the values match
    if (retrievedData.value === testValue) {
      console.log("✅ Value verification passed - stored and retrieved values match!");
    } else {
      console.log("❌ Value verification failed - values don't match");
      console.log(`   Expected: ${testValue}`);
      console.log(`   Retrieved: ${retrievedData.value}`);
    }

    // Test 5: Clean up - delete the test key
    console.log("");
    console.log("4️⃣ Cleaning up test key...");
    const deleteResponse = await fetch(`${KV_URL}/kv/${testKey}`, {
      method: "DELETE",
      headers: {
        "Authorization": `Bearer ${ACCESS_TOKEN}`,
      },
    });

    if (deleteResponse.ok) {
      console.log("✅ Test key cleaned up successfully");
    } else {
      console.log("⚠️  Failed to clean up test key (non-critical)");
    }

    console.log("");
    console.log("🎉 All tests completed successfully!");
    console.log("✅ Your remote KV connection is working properly!");

  } catch (error) {
    console.error("❌ Test failed:");
    console.error(`   Error: ${error.message}`);
    console.error("");
    console.error("🔍 Troubleshooting tips:");
    console.error("   - Check if the server IP and port are correct");
    console.error("   - Verify the access token is valid");
    console.error("   - Ensure the server is running and accessible");
    console.error("   - Check firewall settings");
    
    Deno.exit(1);
  }
}

// Run the test
if (import.meta.main) {
  await testKVConnection();
}