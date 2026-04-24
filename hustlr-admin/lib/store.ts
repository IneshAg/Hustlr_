import { create } from 'zustand';
import { SimParams, SimResult, runSimulation } from './constants';

type StressStore = {
  params: SimParams;
  result: SimResult | null;
  computing: boolean;
  setParam: <K extends keyof SimParams>(key: K, value: SimParams[K]) => void;
  loadPreset: (p: Partial<SimParams>) => void;
};

const DEFAULT_PARAMS: SimParams = {
  workers: 8000,
  days: 3,
  pctBasic: 30,
  pctStandard: 50,
  pctFull: 20,
  realizationRate: 80,
};

let debounceTimer: ReturnType<typeof setTimeout> | null = null;

export const useStressStore = create<StressStore>((set, get) => ({
  params: DEFAULT_PARAMS,
  result: runSimulation(DEFAULT_PARAMS),
  computing: false,

  setParam: (key, value) => {
    const newParams = { ...get().params, [key]: value };
    set({ params: newParams, computing: true });

    if (debounceTimer) clearTimeout(debounceTimer);
    debounceTimer = setTimeout(() => {
      const result = runSimulation(newParams);
      set({ result, computing: false });
    }, 150);
  },

  loadPreset: (p) => {
    const newParams = { ...get().params, ...p };
    set({ params: newParams, computing: true });
    if (debounceTimer) clearTimeout(debounceTimer);
    debounceTimer = setTimeout(() => {
      set({ result: runSimulation(newParams), computing: false });
    }, 150);
  },
}));
