import { useState } from "react";
import { StyledSelect } from "../../components/ui/StyledSelect/StyledSelect";
import { useMultiWatch } from "../../context/MultiWatchContext";
import { useSports } from "../../context/SportsContext";
import { components } from "react-select";

const CheckboxOption = (props: any) => {
  return (
    <components.Option {...props}>
      <input
        type="checkbox"
        checked={props.isSelected}
        readOnly
        style={{ marginRight: 8 }}
      />
      <label>{props.label}</label>
    </components.Option>
  );
};
export const MultiWatchContentEmpty = () => {
    const { allOfTodaysGames } = useSports();
    const { multiWatch, addGameToMultiWatch } = useMultiWatch();

    const [selectedGames, setSelectedGames] = useState<any[]>([]);


    const options = allOfTodaysGames
        .filter((g) => !multiWatch.some((mw) => mw.id === g.id))
        .map((g) => ({
            value: g,
            label: `${g.homeTeam.abbrev} vs ${g.awayTeam.abbrev}`,
        }));

    const handleAddAll = () => {
        selectedGames.forEach((opt) => {
            addGameToMultiWatch(opt.value);
        });

        setSelectedGames([]);
    };

    return (
        <div className="multi-watch-empty">
            <span>No Multi Watch Games</span>

<StyledSelect
  options={options}
  isMulti
  value={selectedGames}
  placeholder="Select games..."

  closeMenuOnSelect={false}
  hideSelectedOptions={false}

  components={{ Option: CheckboxOption }}

  onChange={(opts) => setSelectedGames(opts ? [...opts] : [])}
/>

            <button
                className="multi-watch-add-btn"
                disabled={selectedGames.length === 0}
                onClick={handleAddAll}
            >
                Add Selected Games
            </button>
        </div>
    );
};