import { execSync, spawn } from 'node:child_process';
import os from 'node:os';
import type { FastifyBaseLogger } from 'fastify';

import { ForgeTestLogVerbosity } from './constants';
import { ForgeTestLogFormat } from './constants';
import type {
  ForgeData,
  ForgeTestLogJSON,
  SimulationForgeData,
  SimulationRequest,
  SimulationResponse,
} from './types';

// NOTE: `spawnSync` is replaced with `spawn` because OS can't handle some Forge's verbose output synchronously, and
// it ENOBUFS errors (way too much data being written to stdout/stdeer).
async function spawnAsync(
  logger: FastifyBaseLogger,
  command: string,
  args: string[] = [],
  options: {
    env?: NodeJS.ProcessEnv;
    cwd?: string;
    encoding?: BufferEncoding;
    shell?: boolean;
  } = {},
): Promise<{ stdout: string; stderr: string }> {
  return new Promise((resolve, reject) => {
    const child = spawn(command, args, {
      ...options,
      shell: options.shell ?? true, // default to shell true for parity with CLI usage
      env: { ...process.env, ...options.env },
    });

    let stdout = '';
    let stderr = '';

    if (child.stdout) {
      child.stdout.on('data', (data) => {
        stdout += data.toString(options.encoding ?? 'utf-8');
      });
    }

    if (child.stderr) {
      child.stderr.on('data', (data) => {
        stderr += data.toString(options.encoding ?? 'utf-8');
      });
    }

    child.on('error', (error) => {
      reject(new Error(`Failed to start process: ${error.message}`));
    });

    child.on('close', (code) => {
      if (code !== 0 || !stdout) {
        logger.error('----- stdout -----');
        logger.error(stdout);
        logger.error('----- stderr -----');
        logger.error(stderr);
        logger.error('------------------');
        reject(
          new Error(
            `Forge exited with code ${code}. See logs above for stdout/stderr.`,
          ),
        );
        return;
      }

      resolve({ stdout, stderr });
    });
  });
}

function getForgePath(): string {
  try {
    const forgePath = execSync(
      os.platform() === 'win32' ? 'where forge' : 'which forge',
      {
        encoding: 'utf-8',
      },
    ).trim();
    if (!forgePath) {
      throw new Error(
        "Missing 'forge' binary on the system. Make sure 'foundry' is properly installed",
      );
    }
    return forgePath;
  } catch (error) {
    throw new Error(`Error finding 'forge' binary: ${error}`);
  }
}

function getForgeData(forgeData?: ForgeData): SimulationForgeData {
  const path = getForgePath();
  const profile = forgeData?.profile ?? 'default';
  const contract = forgeData?.contract ?? 'SimulateEnsoCheckout_Fork_Test';
  const contractABI = [] as JSON[]; // TODO
  const test = forgeData?.contract ?? 'test_simulateHandleOps_1';
  const testRelativePath =
    forgeData?.contract ??
    `test/simulators/enso-checkout/tests/${contract}.t.sol`;
  const rpcUrl = forgeData?.rpcUrl ?? '127.0.0.1:8545';
  const logFormat = forgeData?.logFormat ?? ForgeTestLogFormat.JSON;
  const logVerbosity = forgeData?.logVerbosity ?? ForgeTestLogVerbosity.X4V;
  const isTxDataLogged = forgeData?.isTxDataLogged ?? true; // TODO: undo
  const isTestResultsLogged = forgeData?.isTestResultsLogged ?? true; // TODO: undo

  return {
    path,
    profile,
    contract,
    contractABI,
    test,
    testRelativePath,
    rpcUrl,
    logFormat,
    logVerbosity,
    isTxDataLogged,
    isTestResultsLogged,
  };
}

export async function simulateShortcutsOnForge(
  request: SimulationRequest,
  logger: FastifyBaseLogger,
): Promise<SimulationResponse> {
  const forgeData = getForgeData(request.forgeData);

  if (forgeData.isTxDataLogged) {
    logger.info('Simulation JSON Data Sent to Forge:');
    logger.info(request);
  }

  // NOTE: foundry JSON parsing cheatcodes don't support multidimensional arrays, therefore we stringify them
  const simulationJsonData = {
    shortcutData: request.shortcutData,
    backendSigner: request.backendSigner,
    ensoReceiver: request.ensoReceiver,
    signaturePaymaster: request.signaturePaymaster,
    bundler: request.bundler,
    entryPoint: request.entryPoint,
    handleOpsCalldata: request.handleOpsCalldata ?? '',
  };

  const forgeCmd = os.platform() === 'win32' ? 'forge.cmd' : 'forge'; // ! untested on Windows
  // NOTE: `spawnSync` forge call return can optionally be read from both `return.stdout` and `return.stderr`, and processed.
  // NOTE: calling forge with `--json` will print the deployment information as JSON.
  // NOTE: calling forge with `--gas-report` will print the gas report.
  // NOTE: calling forge with `-vvv` prevents too much verbosity (i.e. `setUp` steps), but hides traces from successful
  // tests. To make visible successful test traces, use `-vvvv`.
  const { stdout, stderr } = await spawnAsync(
    logger,
    forgeCmd,
    [
      'test',
      '--match-contract',
      forgeData.contract,
      '--match-test',
      forgeData.test,
      forgeData.logVerbosity,
      forgeData.logFormat,
      '--fork-url',
      forgeData.rpcUrl,
    ],
    {
      encoding: 'utf-8',
      env: {
        FOUNDRY_PROFILE: forgeData.profile,
        PATH: `${process.env.PATH}:${forgeData.path}"`,
        SIMULATION_JSON_DATA: JSON.stringify(simulationJsonData),
        TERM: process.env.TER || 'xterm-256color',
        FORCE_COLOR: '1',
      },
    },
  );

  if (!stdout) {
    throw new Error(
      "Unexpected error calling 'forge'. " +
        `Reason: it didn't error but 'stdout' is falsey: ${stdout}. 'stderr' is: ${stderr}`,
    );
  }

  if ([ForgeTestLogFormat.DEFAULT].includes(forgeData.logFormat)) {
    logger.info(stdout);
    throw new Error('Forced termination to inspect forge test log');
  }

  let forgeTestLog: ForgeTestLogJSON;
  try {
    forgeTestLog = JSON.parse(stdout) as ForgeTestLogJSON;
  } catch (error) {
    throw new Error(
      `Unexpected error parsing 'forge' JSON output. Reason: ${error}`,
    );
  }

  // Process JSON result
  const testLog =
    forgeTestLog[`${forgeData.testRelativePath}:${forgeData.contract}`];
  const setUpResult = testLog.test_results['setUp()']; // NOTE: present only if `-vvvvv` or if `setUp()` failed

  if (setUpResult?.status === 'Failure') {
    logger.error('Result:');
    logger.error(setUpResult);

    return {
      success: false,
      message:
        "Forge simulation failed in 'setUp()'. Uncomment '--json' and re-run this script to inspect the forge logs",
    };
  }

  const testResult = testLog.test_results[`${forgeData.test}()`];

  if (forgeData.isTestResultsLogged) {
    logger.info('Simulation Forge Decoded Logs:');
    logger.info(testResult.decoded_logs.join('\n'));
  }

  if (testResult.status === 'Failure') {
    logger.error('Result:');
    logger.error(testResult);

    return {
      success: false,
      message: `Forge simulation failed in '${forgeData.test}'. Uncomment '--json' and re-run this script to inspect the forge logs`,
    };
  }

  return {
    success: true,
    message: 'Forge test completed successfully',
    output: testLog.test_results,
  };
}
