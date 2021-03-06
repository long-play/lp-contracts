module.exports = {
  networks: {
    staging: {
      gas: 4712388,
      host: "localhost",
      port: 8545,
      network_id: "*" // Match any network id
    },
    alpha: {
      gas: 7000000,
      host: "localhost",
      port: 8545,
      network_id: "*" // Match any network id
    }
  }
};
