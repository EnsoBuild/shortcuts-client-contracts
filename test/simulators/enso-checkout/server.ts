import Fastify, {
  FastifyInstance,
  FastifyReply,
  FastifyRequest,
} from 'fastify';

import { simulateShortcutsOnForge } from './forge';
import type {
  SimulationRequest,
  SimulationResponse,
  HealthResponse,
} from './types';
import { mockRequestBody1 } from './mocks/simulationRequests';

const fastify: FastifyInstance = Fastify({
  logger: {
    transport: {
      target: 'pino-pretty',
      options: {
        colorize: true, // enable ANSI colors
        translateTime: 'SYS:standard',
        ignore: 'pid,hostname', // optional
        singleLine: false, // allow multiline
      },
    },
  },
});

// Configuration
const PORT: number = parseInt(process.env.SIM_ENSO_CHECKOUT_PORT || '3000', 10);

// POST /simulate endpoint
fastify.post<{ Body: SimulationRequest }>(
  '/simulate',
  async (
    request: FastifyRequest<{ Body: SimulationRequest }>,
    _reply: FastifyReply,
  ): Promise<SimulationResponse> => {
    try {
      const { body } = request;

      // Log the received payload
      fastify.log.info('Received simulation request: %o', body);

      // Run forge test with payload & process JSON results
      // TODO: uncomment out
      // return await simulateShortcutsOnForge(body, fastify.log);
      return await simulateShortcutsOnForge(mockRequestBody1, fastify.log);
    } catch (error) {
      const errorMessage =
        error instanceof Error ? error.message : String(error);
      fastify.log.error('Error in /simulate endpoint: %s', errorMessage);

      // Always return 200 with success: false
      return {
        success: false,
        message: `Simulation failed: ${errorMessage}`,
      };
    }
  },
);

// Health check endpoint
fastify.get('/health', async (): Promise<HealthResponse> => {
  return {
    status: 'ok',
    timestamp: new Date().toISOString(),
  };
});

// Start server
const start = async (): Promise<void> => {
  try {
    await fastify.listen({ port: PORT, host: '0.0.0.0' });
    console.log(`🚀 Server running on http://localhost:${PORT}`);
    console.log(`📝 POST /simulate - Run forge test`);
    console.log(`❤️  GET /health - Health check`);
    console.log(`\nPress Ctrl+C to stop the server`);
  } catch (err) {
    const errorMessage = err instanceof Error ? err.message : String(err);
    fastify.log.error('Failed to start server: %s', errorMessage);
    process.exit(1);
  }
};

// Graceful shutdown
process.on('SIGINT', async () => {
  console.log('\n🛑 Shutting down server...');
  await fastify.close();
  process.exit(0);
});

start();
