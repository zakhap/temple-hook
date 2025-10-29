import { CharitableDonationTaken } from "../generated/SimpleTempleHook/SimpleTempleHook";
import { CharitableDonation } from "../generated/schema";

export function handleCharitableDonation(event: CharitableDonationTaken): void {
  let id = event.transaction.hash.toHex() + "-" + event.logIndex.toString();
  let donation = new CharitableDonation(id);

  donation.user = event.params.user;
  donation.poolId = event.params.poolId;
  donation.donationAmount = event.params.donationAmount;
  donation.donationCurrency = event.params.donationCurrency;
  donation.charityEIN = event.params.charityEIN;
  donation.taxReceiptStatement = event.params.taxReceiptStatement;
  donation.timestamp = event.params.timestamp;
  donation.blockNumber = event.block.number;
  donation.transactionHash = event.transaction.hash;

  donation.save();
}
