import type {
  ForgeTestLogFormat,
  ForgeTestLogVerbosity,
  TokenType,
} from './constants';

export type AddressArg = `0x${string}`;
export type HexString = `0x${string}`;

export interface JsonFragmentType {
  readonly name?: string;
  readonly indexed?: boolean;
  readonly type?: string;
  readonly internalType?: any; // @TODO: in v6 reduce type
  readonly components?: ReadonlyArray<JsonFragmentType>;
}

export interface JsonFragment {
  readonly name?: string;
  readonly type?: string;

  readonly anonymous?: boolean;

  readonly payable?: boolean;
  readonly constant?: boolean;
  readonly stateMutability?: string;

  readonly inputs?: ReadonlyArray<JsonFragmentType>;
  readonly outputs?: ReadonlyArray<JsonFragmentType>;

  readonly gas?: string;
}

export interface ForgeData {
  profile?: string;
  contract?: string;
  test?: string;
  testRelativePath?: string;
  rpcUrl?: string;
  logFormat?: ForgeTestLogFormat;
  logVerbosity?: ForgeTestLogVerbosity;
  isTxDataLogged?: boolean;
  isTestResultsLogged?: boolean;
}

export interface ShortcutData {
  tokensInFundingRequired: boolean[];
  tokensInTypes: TokenType[];
  tokensIn: AddressArg[];
  amountsIn: string[]; // BigNumberish
  tokensInHolders: AddressArg[];
}

export interface PackedUserOperation {
  sender: AddressArg;
  nonce: HexString;
  initCode: HexString;
  callData: HexString;
  accountGasLimits: HexString;
  preVerificationGas: string; // BigNumberish
  gasFees: HexString;
  paymasterAndData: HexString;
  signature: HexString;
}

export interface HandleOps {
  ops: PackedUserOperation[];
  beneficiary: AddressArg;
}

export interface SimulationRequest {
  [key: string]: any;
  forgeData?: ForgeData;
  shortcutData: ShortcutData;
  backendSigner: AddressArg;
  ensoReceiver: AddressArg; // NOTE: counterfactual
  signaturePaymaster: AddressArg;
  bundler: AddressArg;
  entryPoint: AddressArg;
  // handleOps?: HandleOps; // NOTE: disabled
  handleOpsCalldata: HexString;
}

export interface SimulationResponse {
  success: boolean;
  output?: ForgeTestLogJSONTest['test_results'];
  error?: string;
  message: string;
}

export interface HealthResponse {
  status: string;
  timestamp: string;
}

export interface SimulationForgeData {
  path: string;
  profile: string;
  contract: string;
  contractABI: JSON[];
  test: string;
  testRelativePath: string;
  rpcUrl: string;
  logFormat: ForgeTestLogFormat;
  logVerbosity: ForgeTestLogVerbosity;
  isTxDataLogged: boolean;
  isTestResultsLogged: boolean;
}

export interface ShortcutToSimulateForgeData {
  shortcutName: string;
  blockNumber: number;
  blockTimestamp: number;
  delegate: AddressArg;
  txData: string;
  txValue: string;
  tokensIn: AddressArg[];
  tokensInTypes: TokenType[];
  tokensInIds: string[];
  tokensInHolders: AddressArg[];
  amountsIn: string[];
  // NOTE: `requiresFunding` triggers the logic that funds the wallet with each `tokensIn` and `amountsIn`.
  // 1st tx probably requires it set to `true`. If further txs have it set to `true` as well it may
  // skew the simulation results (e.g., tokens dust amounts). Use it thoughtfully.
  requiresFunding: boolean;
  tokensOut: AddressArg[];
  tokensDust: AddressArg[];
  trackedAddresses: AddressArg[];
}

export interface ForgeTestLogJSONTest {
  duration: { secs: number; nanos: number };
  test_results: {
    [test: string]: {
      status: string;
      reason: null | string;
      counterexample: null | string;
      logs: {
        address: AddressArg;
        topics: string[];
        data: string;
      }[];
      decoded_logs: string[];
      labeled_addresses: Record<AddressArg, string>;
    };
  };
}

export interface ForgeTestLogJSON {
  [path: string]: ForgeTestLogJSONTest;
}
