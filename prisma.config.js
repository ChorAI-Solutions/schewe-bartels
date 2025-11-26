// eslint-disable-next-line @typescript-eslint/no-require-imports
const { defineConfig } = require("@prisma/config");

const datasourceUrl = process.env.DATABASE_URL;

if (!datasourceUrl) {
  throw new Error(
    "DATABASE_URL is not set. Please define it before running Prisma commands."
  );
}

module.exports = defineConfig({
  schema: "./prisma/schema.prisma",
  datasource: {
    db: {
      provider: "postgresql",
      url: datasourceUrl,
    },
  },
});

