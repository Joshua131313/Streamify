export const useLocalStorage = () => {
  const get = <T>(key: string, defaultValue: T): T => {
    try {
      const stored = localStorage.getItem(key);
      if (!stored) return defaultValue;
      return JSON.parse(stored) as T;
    } catch {
      return defaultValue;
    }
  };

  const set = <T>(key: string, value: T) => {
    localStorage.setItem(key, JSON.stringify(value));
  };

  const append = <T>(key: string, item: T) => {
    const current = get<T[]>(key, []);
    const updated = [...current, item];
    set(key, updated);
    return updated;
  };
  const upsertShowHistory = (key: string, newItem: any) => {
    const current = JSON.parse(localStorage.getItem(key) || "[]");

    const updated = [
      ...current.filter((item: any) => item.showId !== newItem.showId),
      newItem
    ];

    localStorage.setItem(key, JSON.stringify(updated));
  };
  const remove = <T>(
    key: string,
    predicate: (item: T) => boolean
  ) => {
    const current = get<T[]>(key, []);
    const updated = current.filter(item => !predicate(item));
    set(key, updated);
    return updated;
  };

  const has = <T>(
    key: string,
    value: T,
    predicate?: (item: T) => boolean
  ): boolean => {
    const stored = localStorage.getItem(key);
    if (!stored) return false;

    try {
      const parsed = JSON.parse(stored);

      if (Array.isArray(parsed)) {
        if (predicate) return parsed.some(predicate);

        return parsed.some(
          (item) => JSON.stringify(item) === JSON.stringify(value)
        );
      }

      return JSON.stringify(parsed) === JSON.stringify(value);
    } catch {
      return false;
    }
  };

  const clear = (key: string) => {
    localStorage.removeItem(key);
  };

  return { get, set, append, remove, has, clear, upsertShowHistory };
};
