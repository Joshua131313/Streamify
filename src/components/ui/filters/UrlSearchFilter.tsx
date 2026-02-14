import { useSearchParams } from "react-router-dom";
import type { TLabelValue } from "../../../types/tmdb";
import { StyledSelect } from "../StyledSelect/StyledSelect";

interface Props {
  param: string;
  options: TLabelValue[];
  includeAll?: boolean;
  defaultOption?: TLabelValue; 
}

export const UrlSelectFilter = ({
  param,
  options,
  includeAll,
  defaultOption,
}: Props) => {
  const [searchParams, setSearchParams] = useSearchParams();

  const urlValue = searchParams.get(param);

  const finalOptions: TLabelValue[] = [
    ...(includeAll ? [{ value: "", label: "All" }] : []),
    ...options,
  ];

  const fallback =
    defaultOption ??
    (includeAll ? { value: "", label: "All" } : null);

  const value =
    finalOptions.find((o) => o.value === urlValue) ?? fallback;

  const setParam = (val: string) => {
    const params = new URLSearchParams(searchParams);
    val ? params.set(param, val) : params.delete(param);
    setSearchParams(params);
  };

  return (
    <StyledSelect<TLabelValue, false>
      options={finalOptions}
      value={value}
      onChange={(opt) => setParam(opt?.value ?? "")}
    />
  );
};
