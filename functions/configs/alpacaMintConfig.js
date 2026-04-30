import fs from "fs";
import dotenv from "dotenv";
import {
  Location,
  ReturnType,
  CodeLanguage,
} from "@chainlink/functions-toolkit";
dotenv.config();

const requestConfig = {
  source: fs.readFileSync("./functions/sources/alpacaBalance.js").toString(),
  codeLocation: Location.Inline,
  secrets: {
    alpacaKey: process.env.ALPACA_API_KEY,
    alpacaSecret: process.env.ALPACA_SECRET_KEY,
  },
  secretsLocation: Location.DONHosted,
  args: [],
  codeLanguage: CodeLanguage.JavaScript,
  expectedReturnType: ReturnType.uint256,
};

export default requestConfig;
