import { useSearchParams } from "react-router-dom";
import type { TLabelValue, TMediaType } from "../../../types/tmdb"
import { getGenresByMedia } from "../../../data/TMDBGenres";
import { StyledSelect } from "../StyledSelect/StyledSelect";

interface Props {
    mediaType: TMediaType | "all";
    includeAll?: boolean;
}

export const GenreFilter = (props: Props) => {
    const { mediaType, includeAll } = props;
    const [searchParams, setSearchParams] = useSearchParams();

    const urlGenre = searchParams.get("genre");

    const options: TLabelValue[] = [
        ...(includeAll ? [{value: "", label: "All"}] : []),
        ...getGenresByMedia(mediaType)
    ];

    const value =
        options.find(o => o.value === urlGenre) ?? (includeAll ? { value: "", label: "All"} : null);

    const setParam = (val: string) => {
        const params = new URLSearchParams(searchParams);
        val ? params.set("genre", val) : params.delete("genre");
        setSearchParams(params);
    }

    return (
        <StyledSelect<TLabelValue, false>
            options={options}
            value={value}
            onChange={(opt) => setParam(opt?.value ?? "")}
        />
    )
}