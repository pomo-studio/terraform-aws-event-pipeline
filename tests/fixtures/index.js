// Minimal Lambda handler — fixture for unit tests only
// Not intended for production use
exports.handler = async (event) => {
  const failures = [];

  for (const record of event.Records) {
    try {
      console.log("Processing:", record.body);
    } catch (err) {
      failures.push({ itemIdentifier: record.messageId });
    }
  }

  return { batchItemFailures: failures };
};
