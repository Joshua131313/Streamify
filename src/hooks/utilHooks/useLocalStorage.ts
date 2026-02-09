export const useLocalStorage = () => {
  // ---------- GET ----------
  const get = <T>(key: string, defaultValue: T): T => {
    try {
      const stored = localStorage.getItem(key);
      if (!stored) return defaultValue;
      return JSON.parse(stored) as T;
    } catch {
      return defaultValue;
    }
  };

  // ---------- SET / REPLACE ----------
  const set = <T>(key: string, value: T) => {
    localStorage.setItem(key, JSON.stringify(value));
  };

  // ---------- APPEND (arrays only) ----------
  const append = <T>(key: string, item: T) => {
    const current = get<T[]>(key, []);
    const updated = [...current, item];
    set(key, updated);
    return updated;
  };

  // ---------- REMOVE ITEM ----------
  const remove = <T>(
    key: string,
    predicate: (item: T) => boolean
  ) => {
    const current = get<T[]>(key, []);
    const updated = current.filter(item => !predicate(item));
    set(key, updated);
    return updated;
  };

  // ---------- HAS ----------
  const has = <T>(
    key: string,
    value: T,
    predicate?: (item: T) => boolean
  ): boolean => {
    const stored = localStorage.getItem(key);
    if (!stored) return false;

    try {
      const parsed = JSON.parse(stored);

      // If array → search inside
      if (Array.isArray(parsed)) {
        if (predicate) return parsed.some(predicate);

        // fallback deep compare
        return parsed.some(
          (item) => JSON.stringify(item) === JSON.stringify(value)
        );
      }

      // Single value → direct compare
      return JSON.stringify(parsed) === JSON.stringify(value);
    } catch {
      return false;
    }
  };

  // ---------- CLEAR ----------
  const clear = (key: string) => {
    localStorage.removeItem(key);
  };

  return { get, set, append, remove, has, clear };
};
