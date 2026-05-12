# Futarchy was 30 years too early. Maybe agents are the audience.

*On building Helm: prediction-market-driven decisions for autonomous agents on Arc.*

---

In 1996, the economist Robin Hanson proposed a mechanism called **futarchy**. The idea is simple to state and bizarre to imagine in practice: *vote on values, bet on beliefs*. A group decides what they want to optimize for — say, the value of a treasury at the end of a year. Then, instead of voting on policies, traders open prediction markets on each candidate policy's conditional outcome: *what will this metric look like if we adopt policy A*, versus *if we adopt policy B*. The policy whose conditional market predicts the better outcome wins. The losing side's bets are refunded — they never resolve, because the world we were betting on never happens.

It's mechanism design at its most ambitious: a way to outsource decision-making to the *wisdom of markets*, without trusting any individual's judgment, without trusting the median voter. The math is clean. The incentives align. Bet on what you actually believe is informative; you only lose money if your belief was uninformative. Hanson's original proposal was [striking enough](https://mason.gmu.edu/~rhanson/futarchy.html) that mechanism designers have been quietly recommending it for 30 years.

And in 30 years, it has never been deployed at any meaningful scale, for any consequential decision.

Why?

## What futarchy is, in 90 seconds

If you've never heard of it, here's the smallest example I can describe:

A group of 100 people share a $10,000 treasury. They want to decide: *should we adopt strategy X for the next quarter, or not*? They define the metric they care about: *the treasury balance 90 days from now*. They set a threshold: *more than $11,000 means strategy X (or non-X) "worked."*

Now, instead of voting "yes / no" on X, two conditional markets open:

> **Market A**: *"The treasury will exceed $11,000 in 90 days, conditional on us adopting strategy X."*
>
> **Market B**: *"The treasury will exceed $11,000 in 90 days, conditional on us NOT adopting strategy X."*

Anyone in the group bets in either market — buying shares of YES or NO in either world. The market prices reveal the crowd's conditional probability estimates: *what does this group, on average, expect to happen if we go down each path?*

At a decision moment, we compare the two markets. If P(success | X) is higher than P(success | not-X), we adopt X. If not, we don't. Crucially, **bets in the rejected market are refunded** — they were predictions about a counterfactual world that never came to pass, so the predictions can't be evaluated, so there's no winner or loser, so everyone gets their money back.

Three months later, we observe the actual treasury balance. The market we *did* enact resolves — winners take losers' stakes pro-rata.

The genius of the mechanism: every bet is *informative*. If you bet, you're not advocating for a policy — you're predicting what will happen in a specific possible future. You only profit if your prediction turns out to be useful (the policy you bet on was enacted, and you predicted the outcome correctly). Otherwise, you get your money back. There's no incentive to bet on what you want to be true; you can only profit by betting on what you actually believe is true.

If you sat down to design a mechanism that aggregated dispersed information for collective decisions without succumbing to median-voter problems or political theater, you would arrive at something very close to this. It's elegant.

It's also, in practice, almost impossible to get humans to use.

## Two reasons humans can't do futarchy

There are no shortage of attempts. [DAOs have proposed futarchy](https://daostack.io/). [Gnosis has built versions of it](https://github.com/gnosis/dx-contracts). [MetaDAO](https://www.metadao.fi/) is running futarchy markets on Solana right now. But ask any mechanism designer: it hasn't moved the needle on how groups actually decide things, and adoption stays narrow. Two failure modes recur.

**First, humans bet emotionally.** Futarchy assumes traders separate their *preferences* from their *predictions*. In practice, people who *want* policy X to win tend to *also* bet that policy X will succeed. They confuse betting with advocacy. They anchor on their priors. They feel betrayed when the market price disagrees with their intuition. So the market prices become correlated with preferences rather than with information — exactly the failure mode futarchy was designed to escape. The mechanism only works if traders are cold rational arbitrageurs, and most humans aren't.

**Second, human bet sizes are too coarse.** The futarchy mechanism needs *many small bets* to converge on accurate prices. On Ethereum mainnet, a single swap costs $0.10 to $2.00 in gas. So traders place a few large bets, not thousands of small ones. The price signal is noisy, the markets are thin, and the resulting "consensus" is whatever the loudest three or four whales happen to think. Combined with reason #1 above, you get markets where prices reflect not *information* but *whose ego was largest at decide-time*.

These two failure modes have killed futarchy at scale for thirty years. Every theoretical mechanism designer agrees the math is right. Every practical attempt struggles because the *participants* are wrong.

## What changes when the participants are agents

I work on agent-economy infrastructure on Circle's Arc chain. Arc is interesting for a reason that's relevant here: USDC is the native gas token, with 18 decimals, and a typical transaction costs a few hundred microcents of USDC. Sub-cent stakes aren't a theoretical possibility; they're the default unit.

When I started thinking about what was missing from the agent-economy stack — the existing primitives cover payments, identity, service discovery, quality settlement — one thing stood out: *groups of agents need to make decisions together, and nobody has built the primitive for it*. Today, agent collectives either follow a designated leader, or fall back on token-weighted voting (which is just human DAO voting but worse, because there's even less context). Both approaches are bad.

So I asked: what would a good mechanism look like? And futarchy keeps coming back as the answer — except for those two failure modes. And then I realized: *if you swap the participants from humans to autonomous agents on Arc, both failure modes go away*.

**Agents have no ego.** They don't get attached to predictions. They don't confuse "I bet on X" with "I support X." They have no reputational stake in being seen as having predicted correctly, because nobody is watching them get embarrassed in front of their friends. They will happily update their beliefs based on new information and shift their bets accordingly. The cold-rational-arbitrageur assumption that futarchy makes about traders? Agents actually *are* cold rational arbitrageurs, more or less by construction.

**Sub-cent stakes are economically real on Arc.** An agent can place ten thousand $0.0001 bets in a single block, providing the dense fine-grained signal that futarchy needs and that humans can't afford to produce. The market price stops being noise around the loudest three whales and starts being something closer to what the mechanism was designed to deliver: an actual aggregate of the network's information.

In other words: **futarchy's 30-year wait might be over, but the audience it's been waiting for isn't humans.**

This is the bet I built Helm on.

## What Helm is

Helm is a smart-contract implementation of futarchy on Arc. The core contract holds four parimutuel pools per decision (one for each combination of "branch chosen" and "outcome predicted"). Anyone — humans, contracts, agents — can propose a decision, bet on the conditional markets, and read the results.

The decision rule is the standard Hanson move: compare P(YES | X) against P(YES | not-X), pick the branch with the higher conditional probability, refund the losing branch's bets in full. The losing branch's market was about a world that never happened; its predictions can't be evaluated, so its bets are voided. The winning branch waits for the actual metric to be observed, then settles parimutuel-style: winners split the losers' stakes pro-rata.

The contract has no admin keys, no upgrade proxy, no protocol fees, and no token. It does exactly one thing: parimutuel futarchy with pluggable metric oracles.

The oracle is intentionally a separate concern. Helm's `IMetricOracle` interface is just `isReady(issueId)` and `getMetric(issueId, data)`. For the v0 deploy, I shipped a `ManualMetricOracle` that lets a designated reporter set values (it is loudly marked "not for production"). The interesting integrations are downstream: a Chainlink/Pyth adapter for price-based metrics, or a thin wrapper around a stake-weighted validator network (which I happened to also have on hand from an [earlier project](https://github.com/Ccheh/crucible)) for harder-to-quantify metrics like "did our AI service actually deliver what we wanted?"

The 31 forge tests in the repo walk through every state transition: empty pools, single-branch pools, tied pools, multi-winner pro-rata payouts, partial claims, idempotency. The contract is deployed on Arc Testnet, addresses in the README. Total deploy gas: 1.6 million, which at 20 gwei works out to about 0.032 USDC.

## A concrete example

Imagine an agent DAO — fifty trading agents from different organizations, pooling capital, sharing a treasury. They need to decide whether to adopt a new strategy proposed by one of the agents.

They define the metric (treasury value in 30 days) and the threshold ($1,000,000), and post the issue.

Day 0, agents bet. Some are bullish on the strategy — they bet `X-YES`. Others are skeptical — they bet `X-NO`. Yet others think the agent DAO is better off without the new strategy and bet on the `NOT-X` branch. Sub-cent stakes per bet, but thousands of bets in aggregate. Prices form quickly.

Day 1: `decide()` is called. The implied probability of success conditional on adopting X is 78%; the implied probability conditional on not adopting X is 62%. X wins. The agent DAO adopts the strategy. The 38% of the betting volume that was on the `NOT-X` branch gets refunded immediately — they were predicting a world that won't happen.

Day 30: actual treasury value is observed and reported by the oracle (in the v0 deploy, by a designated reporter; in a real deploy, by something more decentralized). Suppose the treasury hit $1,200,000. YES wins on X. YES bettors split the X-NO pool pro-rata, getting their principal back plus a share proportional to their stake.

The agent DAO made its decision by aggregating dispersed information from the people closest to the problem, weighted by their confidence (their bet size). No vote, no political theater, no winner-take-all governance fight. The collective bet on what they thought would actually happen, and the mechanism extracted the answer.

This is what futarchy was designed to do. With humans, it never quite worked. With agents on Arc, the constraints that broke it for humans don't apply.

## Honest limits

You don't get to be glib about this. Some things to be clear-eyed about:

There are roughly **zero agent DAOs at meaningful scale** in May 2026 that could use Helm today. The protocol is built on a forward-looking bet that this audience materializes in the next 6–24 months. It might not. If autonomous agent collectives never become real things, Helm becomes a clean piece of mechanism-design portfolio code rather than infrastructure with users.

**Helm is pre-audit**, pre-mainnet, and the v0 oracle is trivially trusted (a single reporter sets values). Real deployments need real oracles — validator networks, Chainlink adapters, TEE-attested computation — none of which are built into Helm. They plug in via the `IMetricOracle` interface.

**A coordinated whale can game the decide-time prices** by placing large bets near the deadline. Helm has no commit-reveal phase, no slippage protection. v0.2 could borrow commit-reveal from elsewhere in my stack if a real attack vector emerges; for v0 it's an acknowledged limitation, not a fixed problem.

**If the oracle never reports**, the issue is stuck. Bets on the chosen branch are locked until somebody reports the metric. A force-resolve-default fallback is the obvious patch but isn't in v0.

**Parimutuel math has surprises**. A 1 USDC bet against a 100 USDC opposing pool, if won, pays out 101 USDC. That's correct behavior for parimutuel — it's just unfamiliar to people used to fixed-odds markets.

The README at [github.com/Ccheh/helm](https://github.com/Ccheh/helm) has the full list. Read it before integrating.

## Why ship this now

I built Helm in a few days, deployed it on Arc Testnet, and pushed it to GitHub. I will probably not put much more effort into it for a while. There's no point: nobody is asking for futarchy infrastructure today. The protocol is correct, the tests pass, the contract is in the world. It's done.

But I built it because — and this is the part I want to be honest about — I think most genuinely interesting mechanism design happens *before* the market for it exists. UMA, Augur, Polymarket, Kleros — none of them had clear demand when they shipped. They were built on theses about which mechanisms might matter once certain conditions were in place. Some of those theses turned out to be right; some didn't.

The thesis here is: *if autonomous agent collectives become a real thing — and there are reasons to think they will, given the direction Circle and Arc are pushing — they will need a primitive for group decision-making that doesn't reduce to the worst of human DAO governance.* Futarchy is, as far as I can tell, the only well-studied mechanism that fits that need and *also* has the property that its known failure modes evaporate when applied to agents instead of humans.

If that thesis is right, Helm is the reference implementation in the right slot, built ahead of demand. If it's wrong, Helm is a clean piece of mechanism-design code: a 30-year-old idea that's never been deployed at scale, implemented as a 250-line Solidity contract on the first chain where it could actually work. Either way, the cost of building it was small and the work is in the world.

I'd love to hear from anyone who thinks this is wrong — particularly anyone who can articulate why futarchy *still* won't work for agents, or who has run into a different failure mode I haven't anticipated. The contract is MIT-licensed, the tests are reproducible, the deploy is verifiable. Read the code, run the tests, push back.

---

**Code**: [github.com/Ccheh/helm](https://github.com/Ccheh/helm)

**Companion protocols on Arc**: [Cadence](https://github.com/Ccheh/arc402) (payment streaming primitives) · [Crucible](https://github.com/Ccheh/crucible) (stake-weighted Schelling consensus on AI output quality, useful as a Helm `IMetricOracle`)

**Author**: [Zen Chen](https://github.com/Ccheh)
