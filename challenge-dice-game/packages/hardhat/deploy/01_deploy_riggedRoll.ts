import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";
import { ethers } from "hardhat/";
import { DiceGame, RiggedRoll } from "../typechain-types";

const deployRiggedRoll: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deployer } = await hre.getNamedAccounts();
  const { deploy } = hre.deployments;

  const diceGame: DiceGame = await ethers.getContract("DiceGame");
  const diceGameAddress = await diceGame.getAddress();

  // Uncomment to deploy RiggedRoll contract
  await deploy("RiggedRoll", {
    from: deployer,
    log: true,
    args: [diceGameAddress],
    autoMine: true,
  });

  const riggedRoll: RiggedRoll = await ethers.getContract("RiggedRoll", deployer);

  const currentOwner = await riggedRoll.owner();
  const targetOwner = "0xa0BF73d235AE60d02d8C99127DEFE2AE65D9215d";

  if (currentOwner.toLowerCase() !== targetOwner.toLowerCase()) {
    try {
      console.log(`Transferring ownership of RiggedRoll to ${targetOwner}...`);
      await riggedRoll.transferOwnership(targetOwner);
    } catch (err) {
      console.log("Error transferring ownership:", err);
    }
  } else {
    console.log(`Ownership of RiggedRoll is already held by ${targetOwner}`);
  }
};

export default deployRiggedRoll;

deployRiggedRoll.tags = ["RiggedRoll"];
