import type { SportStream } from "../../../types/sports/sportsTypes";
import { StyledSelect } from "../StyledSelect/StyledSelect";
import "./StreamSelector.css";

interface Props {
  streams: SportStream[];
  value: SportStream | null;
  onChange: (stream: SportStream | null) => void;
}

export const StreamSelector = (props: Props) => {
  const { streams, value, onChange } = props;

  const options = streams.map((stream, index) => ({
    label: stream.label ?? `Stream ${index + 1}`,
    value: stream,
  }));

  const handleChange = (option: any) => {
    onChange(option?.value ?? null);
  };

  return (
    <div className="stream-selector">
      <StyledSelect
        options={options}
        value={value ? options.find(o => o.value === value) : null}
        onChange={handleChange}
        isMulti={false}
        placeholder="Select stream"
      />
    </div>
  );
};