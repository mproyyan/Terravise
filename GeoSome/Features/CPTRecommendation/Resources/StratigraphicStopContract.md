# Practical Dynamic STOP — exploratory investigation

Active policy: `practical-dynamic-stop-research-1`, literal port of the frozen research policy in cpt_super_learn/results/stratigraphic_uncertainty_v1/practical_dynamic_stop/policy.py.

STOP requires three conditions: original global physical support (P95 distance ratio <=1 and maximum <=1.75); the latest genuine acquired CPT has no coherent material reconstruction/boundary/continuity revision and no measured profile mismatch across >=2 consecutive grid depths; current Uncertainty V3 predictedCoverage >=0.80. Otherwise CONTINUE; absent or invalid genuine history retains the existing internal UNDETERMINED semantics. No fixed CPT count, two confirmations, per-pattern spatial support, residual ambiguity limit, zero coherent ambiguity or unsupported-unit veto.

Coverage is the existing service output: fraction of valid unobserved voxels with calibrated Ic bound <=0.15. It is not a probability of stratigraphic error. UI percentages remain unchanged. Coverage is bound into snapshot identity; domain/value validation does not change the uncertainty computation.

The existing upload chain, ordered prefix, measurement preservation, grid/mask/context/model/build identity, save/reopen and input validity guards remain. A different policy/build invalidates old history. Reopening cannot manufacture a new confirmation. STOP suppresses the existing DQN dispatch; CONTINUE and UNDETERMINED permit it. No mode, toggle, second engine or status is introduced.

This more aggressive policy is authorized for early exploratory investigation, accepting missed geology. It is not certification of final geotechnical design sufficiency or field safety. Known regression: 01_undulating_05 STOP6 precedes CPT9/11 material discoveries. Existing synthetic results and duplicated actual26 profiles do not validate field CPT savings.

The exploratory coverage target was explicitly changed by the user from0.90 to0.80. Other decision criteria and Uncertainty V3 calculations are unchanged. Source/build identity invalidates pre-change history.
