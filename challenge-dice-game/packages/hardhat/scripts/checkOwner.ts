import { ethers } from "hardhat";
import { RiggedRoll } from "../typechain-types";

async function main() {
  const riggedRoll = (await ethers.getContract("RiggedRoll")) as unknown as RiggedRoll;
  const owner = await riggedRoll.owner();
  console.log("RiggedRoll Owner:", owner);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
