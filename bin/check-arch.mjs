// Refuses a non-native (x64, Rosetta) Node on macOS. Run by `prebuild`; does nothing elsewhere.
// Tests only: INKHK3_TEST_PLATFORM / INKHK3_TEST_ARCH override process.platform / process.arch.
const platform = process.env.INKHK3_TEST_PLATFORM || process.platform;
const arch = process.env.INKHK3_TEST_ARCH || process.arch;
if (platform === 'darwin' && arch !== 'arm64') {
  console.error(`error: this Node is a ${arch} build; on macOS it must be a native arm64 build, not Rosetta. ` +
    `Install an arm64 Node 24 ('arch -arm64 nvm install') and retry.`);
  process.exit(1);
}
