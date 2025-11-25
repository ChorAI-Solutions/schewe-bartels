import { PrismaClient } from "@/app/generated/prisma/client";
import { PrismaPg } from "@prisma/adapter-pg";
import { Pool } from "pg";

declare global {
  var prisma: PrismaClient | undefined;
}

const datasourceUrl = process.env.DATABASE_URL;

if (!datasourceUrl) {
  throw new Error(
    "DATABASE_URL is not set. Please define it in your environment before using Prisma."
  );
}

const pool = new Pool({ connectionString: datasourceUrl });
const adapter = new PrismaPg(pool);

export const prisma: PrismaClient = global.prisma ?? new PrismaClient({ adapter });

if (process.env.NODE_ENV !== "production") {
  global.prisma = prisma;
}


