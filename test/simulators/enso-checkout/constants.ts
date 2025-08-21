// Forge test
export enum TokenType {
  NATIVE_ASSET = 0,
  ERC20 = 1,
  ERC721 = 2,
  ERC1155 = 3,
}

export enum ForgeTestLogFormat {
  DEFAULT = '',
  JSON = '--json',
}

export enum ForgeTestLogVerbosity {
  X1V = '-v',
  X2V = '-vv',
  X3V = '-vvv',
  X4V = '-vvvv',
  X5V = '-vvvvv',
}

export enum TraceItemPhase {
  DEPLOYMENT = 'Deployment',
  EXECUTION = 'Execution',
  SETUP = 'Setup',
}

export const DEFAULT_BLOCK_NUMBER = -1;
export const DEFAULT_BLOCK_TIMESTAMP = -1;
export const DEFAULT_TX_AMOUNT_IN_VALUE = '0';
