import type { SportStream } from "../../../types/sports/sportsTypes";
import { PlayerSelect } from "../PlayerSelect/PlayerSelect";
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
    value: stream.provider,
  }));

  const handleChange = (provider: string) => {
    onChange(streams.find(stream => stream.provider === provider) ?? null);
  };

  return (
    <div className="stream-selector">
      <PlayerSelect
        label="Stream source"
        options={options}
        value={value?.provider ?? ""}
        onChange={handleChange}
      />
    </div>
  );
};
