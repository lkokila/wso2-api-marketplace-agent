// Builds the curated OpenAPI definition from the product's devportal-api.yaml, keeping only
// the operations listed in openapi/tools.yaml and the schemas they use. Outputs, in build/:
//   devportal-curated.yaml  definition the MCP server is generated from
//   operations.json         tool-to-backend-operation mappings for the Publisher API
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import yaml from 'js-yaml';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const apimHome = process.env.APIM_HOME;
if (!apimHome) {
    console.error('APIM_HOME is not set');
    process.exit(1);
}
const sourcePath = path.join(apimHome,
    'repository/deployment/server/webapps/api#am#devportal/WEB-INF/classes/devportal-api.yaml');
const source = yaml.load(fs.readFileSync(sourcePath, 'utf8'));
const { tools } = yaml.load(fs.readFileSync(path.join(root, 'openapi/tools.yaml'), 'utf8'));

const paths = {};
for (const tool of tools) {
    const operation = source.paths?.[tool.path]?.[tool.method];
    if (!operation) {
        console.error(`Operation not found in source spec: ${tool.method.toUpperCase()} ${tool.path}`);
        process.exit(1);
    }
    const { 'x-code-samples': _samples, 'x-examples': _examples, parameters = [], ...rest } = operation;
    // Header parameters (If-None-Match, X-WSO2-Tenant) would surface as tool inputs; drop them.
    const toolParameters = parameters.filter((parameter) => {
        const resolved = parameter.$ref
            ? source.components.parameters[parameter.$ref.split('/').pop()]
            : parameter;
        return resolved.in !== 'header';
    });
    paths[tool.path] ??= {};
    paths[tool.path][tool.method] = {
        ...rest,
        ...(toolParameters.length > 0 && { parameters: toolParameters }),
        operationId: tool.name,
        summary: tool.description,
        description: tool.description,
    };
}

// Copy only the components reachable from the selected operations.
const components = {};
const visit = (node) => {
    if (Array.isArray(node)) {
        node.forEach(visit);
    } else if (node && typeof node === 'object') {
        for (const [key, value] of Object.entries(node)) {
            if (key === '$ref' && typeof value === 'string' && value.startsWith('#/components/')) {
                const [, , section, name] = value.split('/');
                if (!components[section]?.[name]) {
                    const target = source.components?.[section]?.[name];
                    if (!target) throw new Error(`Unresolved reference: ${value}`);
                    (components[section] ??= {})[name] = target;
                    visit(target);
                }
            } else {
                visit(value);
            }
        }
    }
};
visit(paths);
components.securitySchemes = source.components.securitySchemes;

const curated = {
    openapi: source.openapi,
    info: {
        title: 'WSO2 API Manager - Developer Portal (agent tools)',
        description: 'Curated subset of the Developer Portal REST API exposed as MCP tools.',
        version: source.info.version,
    },
    servers: [{ url: `${process.env.APIM_MGT_URL ?? 'https://localhost:9443'}/api/am/devportal/v3` }],
    paths,
    components,
};

const operations = tools.map((tool) => ({
    feature: 'TOOL',
    backendOperationMapping: {
        backendId: '',
        backendOperation: { target: tool.path, verb: tool.method.toUpperCase() },
    },
}));

const buildDir = path.join(root, 'build');
fs.mkdirSync(buildDir, { recursive: true });
fs.writeFileSync(path.join(buildDir, 'devportal-curated.yaml'), yaml.dump(curated, { lineWidth: 120, noRefs: true }));
fs.writeFileSync(path.join(buildDir, 'operations.json'), JSON.stringify(operations, null, 2));
console.log(`Wrote build/devportal-curated.yaml and build/operations.json: ${tools.length} operations, ` +
    `${Object.keys(components.schemas ?? {}).length} schemas`);
