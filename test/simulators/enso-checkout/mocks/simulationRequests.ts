import type { AddressArg, HexString, SimulationRequest } from '../types';
import { TokenType } from '../constants';

const NATIVE_TOKEN = '0xeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee' as AddressArg;
const USDC = '0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48' as AddressArg;
const EnsoAccount = '0x93621DCA56fE26Cdee86e4F6B18E116e9758Ff11' as AddressArg;
const EvilAddress = '0x6666666666666666666666666666666666666666' as AddressArg;

const backendSigner =
  '0xFE503EE14863F6aCEE10BCdc66aC5e2301b3A946' as AddressArg;
const ensoReceiver = '0x241617016230fb1B08fE9AE3A10d308f526FF95C' as AddressArg; // TODO: this is the implementation, not the ERC4337
const bundler = '0x8B2efB5293326e1766Cb5D0855032F150A72B705' as AddressArg;
const entryPoint = '0x0000000071727De22E5E9d8BAf0edAc6f37da032' as AddressArg;
const signaturePaymaster =
  '0xfa66d86a5Efc7632070b1F0b1C639C69a7E7D8C5' as AddressArg; // TODO
const beneficiary = backendSigner;

const handleOpsCalldata =
  '0xdeaddeaddeaddeaddeaddeaddeaddeaddeadabba' as HexString;

export const mockRequestBody1 = {
  shortcutData: {
    tokensInFundingRequired: [true, true],
    tokensInTypes: [TokenType.ERC20, TokenType.NATIVE_ASSET],
    tokensIn: [USDC, NATIVE_TOKEN],
    amountsIn: [(100n ** 6n).toString(), (7n ** 18n).toString()],
    tokensInHolders: [
      '0x37305B1cD40574E4C5Ce33f8e8306Be057fD7341',
      '0x0000000000000000000000000000000000000000',
    ],
  },
  backendSigner,
  ensoReceiver,
  signaturePaymaster,
  bundler,
  entryPoint,
  // handleOps: {
  //   beneficiary,
  //   ops: [
  //     {
  //       sender: ensoReceiver,
  //       nonce: '0xdeaddeaddeaddeaddeaddeaddeaddeaddeadbebe' as HexString,
  //       initCode: '0x095ea7b3' as HexString,
  //       callData:
  //         '0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff' as HexString,
  //       accountGasLimits:
  //         '0xdeaddeaddeaddeaddeaddeaddeaddeaddeaddeaddeaddeaddeaddeaddead0000' as HexString,
  //       preVerificationGas: '12345678',
  //       gasFees: '' as HexString,
  //       paymasterAndData: '' as HexString,
  //       signature: '' as HexString,
  //     },
  //   ],
  // },
  handleOpsCalldata,
} as SimulationRequest;
