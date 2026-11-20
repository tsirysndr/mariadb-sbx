#!/usr/bin/env node
import { main } from "../output/Main/index.js";
process.argv[1] = "mariadb-sbx";
main();
