import { Container } from "../../components/layout/Container/Container";
import { StyledSelect } from "../../components/ui/StyledSelect/StyledSelect";
import { useEpisodesContext } from "./EpisodesProvider";
import { FaSearch, FaSortAmountDownAlt, FaSortAmountUpAlt } from "react-icons/fa";
import { Icon } from "../../components/ui/Icon/Icon";
import { Input } from "../../components/ui/Input/Input";

export const EpisodesControls = () => {
    const {
        show,
        seasonNumber,
        setSeasonNumber,
        search,
        setSearch,
        direction,
        setDirection,
    } = useEpisodesContext();

    const seasonOptions = show.seasons?.map((s) => ({
        value: s.season_number,
        label: s.name,
    })) ?? [];

    return (
        <Container className="season-selector-container" styled>
            <div className="season-selector">
                <StyledSelect
                    options={seasonOptions}
                    value={seasonOptions.find((o) => o.value === seasonNumber)}
                    onChange={(opt) => setSeasonNumber(opt?.value ?? 1)}
                    className="select"
                />

                <Input
                    Icon={FaSearch}
                    placeholder="Search episode..."
                    value={search}
                    onChange={(e) => setSearch(e.target.value)}
                />

                <Icon
                    onClick={() => setDirection(direction === "asc" ? "desc" : "asc")}
                    Icon={direction === "asc" ? FaSortAmountDownAlt : FaSortAmountUpAlt}
                />
            </div>
        </Container>
    );
};
