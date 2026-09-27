# Third-party source

`src/math/FullMath.sol` contains the floor `mulDiv` function extracted from
[OpenZeppelin Contracts v5.0.2 Math.sol](https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v5.0.2/contracts/utils/math/Math.sol).
Only that function and its error remain; the library is renamed and the pragma is pinned to 0.8.24. Formatting follows this project.
The original credits Remco Bloemen and Uniswap Labs. The MIT license is retained in
`LICENSES/OpenZeppelin-MIT.txt`. This source is included as an ordinary file; there are no submodules, package downloads, or runtime dependencies.

SHA-256 of the unmodified upstream Math.sol used for extraction: `a6ee779fc42e6bf01b5e6a963065706e882b016affbedfd8be19a71ea48e6e15`.

All test support and the independent reference model are local project source.
