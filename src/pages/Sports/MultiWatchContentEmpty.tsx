import { useState } from "react";
import { StyledSelect } from "../../components/ui/StyledSelect/StyledSelect";
import { useMultiWatch } from "../../context/MultiWatchContext";
import { useSports } from "../../context/SportsContext";
import { components } from "react-select";
import { Button } from "../../components/ui/Button/Button";
import "./Sports.css"
import { FaCheck } from "react-icons/fa";

const CheckboxOption = (props: any) => {
    const { isSelected, data } = props;

    return (
        <components.Option {...props} className="option">
            <div className={`${isSelected ? "checked" : ""} checkbox`}>
                <FaCheck />
            </div>

            <div className="option-content">
                <img src={data.homeLogo} className="team-logo" />
                <span>{data.homeAbbrev}</span>

                <span className="vs">vs</span>

                <img src={data.awayLogo} className="team-logo" />
                <span>{data.awayAbbrev}</span>
            </div>
        </components.Option>
    );
};

const MultiValueLabel = (props: any) => {
  const { data } = props;

  return (
    <components.MultiValueLabel {...props}>
      <div className="multi-chip">
        <img src={data.homeLogo} className="team-logo" />
        <span className="team">{data.homeAbbrev}</span>

        <span className="vs">vs</span>

        <img src={data.awayLogo} className="team-logo" />
        <span className="team">{data.awayAbbrev}</span>
      </div>
    </components.MultiValueLabel>
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
            label: `${g.homeTeam.name} vs ${g.awayTeam.name}`, // keep for fallback/search
            homeLogo: g.homeTeam.logo,
            awayLogo: g.awayTeam.logo,
            homeAbbrev: g.homeTeam.abbrev,
            awayAbbrev: g.awayTeam.abbrev,
        }));

    const handleAddAll = () => {
        selectedGames.forEach((opt) => {
            addGameToMultiWatch(opt.value);
        });

        setSelectedGames([]);
    };

    return (
        <div className="multi-watch-empty">
            <span>Add games to multi-watch</span>

            <StyledSelect
                options={options}
                isMulti
                value={selectedGames}
                placeholder="Select games..."
                getOptionValue={(opt) => opt.value.id}
                closeMenuOnSelect={false}
                hideSelectedOptions={false}

                components={{ Option: CheckboxOption, MultiValueLabel }}

                onChange={(opts) => setSelectedGames(opts ? [...opts] : [])}
            />

            <Button
                onClick={handleAddAll}
                disabled={selectedGames.length === 0}
            >
                Add Selected Games
            </Button>
        </div>
    );
};