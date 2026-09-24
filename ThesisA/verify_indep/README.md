# verify_indep

An implementation of the compression chain written from scratch in Python/NumPy,
independent of both the MATLAB model (Matlab_Sim) and the HLS C++ designs. It is
the "independent implementation" of Appendix D of the thesis report.

Put the 50 raw ColoRadar frames (`frame_0.bin` ... `frame_49.bin`, int16 as
exported by the MATLAB loader) and the HLS stimulus `coloradar_multiframe.bin` in
`raw/` next to these scripts, or point `COLORADAR_RAW` at the folder holding them.
The raw data is not committed.

| Script | What it checks |
|---|---|
| `indep.py` | raw frame -> FX16 (vs HLS stimulus), DRHE lag 1 / lag 12, LPC lags 1,2 / 12,24, bit counts vs HLS, audit numbers. Writes `indep_results.json`. |
| `coefstats.py` | LPC coefficient statistics (thesis Section 8.5.3) |
| `idealdict.py` | ideal S4 dictionaries and order-0 entropies |
| `retrain_complete.py` | dictionaries re-derived on frames 0-4, tested on 5-49 (thesis Section 8.7). Writes `retrain_complete_rerun.json` and compares with `retrain_complete.json`. |
| `rle.py` | R4S4 + run-length coding vs S4 only, ideal dictionaries, on ColoRadar |
