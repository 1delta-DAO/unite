# 1delta Unite

## Limit orders for basis trading using 1inch

Execute pre-action as composed lending operations.

100% Gasless for users.

Partial fils included.

Many lenders supported.

Moonshot: Triggers.

# ToDos

## UI
- Build limit order interface
- Get simple data provision (maybe we do Morpho B first)
- Create default sig setup using 1inch SDK to be able to sign at least default orders
- Build shell for costom data inclusion

## Contracts
- Build lending (contract) APIs with amounts (amounts cannot be encoded on actions as we want to allow partial fills)
- Define states that enables partial fills (validate call from 1inch router and store the partials based on the hash)
- build pre-defined flash loan selection that wraps the fill call (Morpho B is enough here)
- ideally: build it so that there are no additional sigs required asisde of order & lending permits

## Backend
- Build filler API
   - The filler can be a worker  with a simple KV that collects all orders
   - Just run a cron that stores and exposes the orders
   - Build a reader that reads the orders
   - build calldata that uses 1inch aggregation API and flash loan selection (default: Morpho B) to fill an order if possible
