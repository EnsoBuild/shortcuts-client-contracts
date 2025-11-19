import { spawn } from 'child_process';
import { resolve } from 'path';

const testScript = resolve('testGambitMutations.mjs');

// NOTE: append `--verbose true` to see the logs
const commands = [
  [
    `node`,
    [
      testScript,
      '--matchContract',
      'ERC4337CloneFactory_.*_Unit_Concrete_Test',
      '--matchMutant',
      'ERC4337CloneFactory',
    ],
  ],
  [
    `node`,
    [
      testScript,
      '--matchContract',
      'EnsoReceiver.*_Unit_Concrete_Test',
      '--matchMutant',
      'EnsoReceiver',
    ],
  ],
  [
    `node`,
    [
      testScript,
      '--matchContract',
      'SignaturePaymaster.*_Unit_Concrete_Test',
      '--matchMutant',
      'SignaturePaymaster',
    ],
  ],
];

function runCommand(index = 0) {
  if (index >= commands.length) return;

  console.log(`\n> Running mutation test ${index + 1} of ${commands.length}`);
  const [cmd, args] = commands[index];

  const child = spawn(cmd, args, { stdio: 'inherit' });

  child.on('exit', (code) => {
    if (code !== 0) {
      console.error(`❌ Command failed with exit code ${code}`);
      process.exit(code);
    } else {
      runCommand(index + 1);
    }
  });
}

runCommand();
