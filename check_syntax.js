const fs = require("fs");
const luaparse = require("luaparse");
const src = fs.readFileSync("RangeAttack_Aura.lua", "utf8");
try {
  luaparse.parse(src, { luaVersion: "5.3" });
  console.log("luaparse 5.3: syntax OK, " + src.split("\n").length + " lines");
} catch (e) {
  console.log("syntax error: " + e.message);
  process.exit(1);
}
