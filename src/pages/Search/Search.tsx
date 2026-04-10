import { useState } from "react"
import { Container } from "../../components/layout/Container/Container"
import { MediaCard } from "../../components/ui/MediaCard/MediaCard"
import { StyledSelect } from "../../components/ui/StyledSelect/StyledSelect"
import { useMixedMedia } from "../../hooks/mediaHooks/useMixedMedia"
import "./Search.css"
import { Input } from "../../components/ui/Input/Input"
import { FaFilm, FaList, FaSearch, FaTv } from "react-icons/fa"
import { useSearchMedia } from "../../hooks/mediaHooks/useSearchMedia"
import type { TMediaType } from "../../types/tmdb"
import { PageHeader } from "../../components/ui/PageHeader/PageHeader"
import { Icon } from "../../components/ui/Icon/Icon"
import { Title } from "../../components/ui/Title/Title"
import { SearchWithHistory } from "./SearchWithHistoryInput"
import { Loader } from "../../components/ui/Loader/Loader"
import { SEO } from "../../components/SEO"
import type { IconType } from "react-icons"
import { components } from "react-select";

export type Option = {
    value: TMediaType | "multi";
    label: string;
    icon?: IconType;
};
export const selectOptions: Option[] = [
    {
        value: "multi",
        label: "All",
        icon: FaList,
    },
    {
        value: "movie",
        label: "Movies",
        icon: FaFilm
    },
    {
        value: "tv",
        label: "TV Shows",
        icon: FaTv,
    }

]


const CustomSearchOption = (props: any) => {
  const { data } = props;
  const Icon = data.icon;

  return (
    <components.Option {...props}>
      <div style={{ display: "flex", alignItems: "center", gap: "10px" }}>
        {Icon && <Icon size={16} />}
        <span>{data.label}</span>
      </div>
    </components.Option>
  );
};
const CustomSingleValue = (props: any) => {
  const { data } = props;
  const Icon = data.icon;

  return (
    <components.SingleValue {...props}>
      <div style={{ display: "flex", alignItems: "center", gap: "10px" }}>
        {Icon && <Icon size={16} />}
        <span>{data.label}</span>
      </div>
    </components.SingleValue>
  );
};

const Search = () => {
    const { media: trendingToday } = useMixedMedia("/trending/all/day", 20);
    const [option, setOption] = useState<Option>(selectOptions[0]);
    const { executeSearch, setSearch, search, media, hasSearched, isLoading } = useSearchMedia(option.value);

    const trendingTodayRow = trendingToday.map(media => {
        return (
            <MediaCard media={media} key={media.id} />
        )
    })
    const searchResultsRow = media.map(media => {
        return (
            <MediaCard media={media} key={media.id} />
        )
    })


    return (
        <div className="search-page">
            <SEO
                title="Search"
                description="Search movies and TV shows"
            />
            <PageHeader
                title="Browse Through The Catalog"
                subTitle="Search through thousands of movies, TV shows and anime series"
                controls={
                    <>
                        <StyledSelect<Option, false>
                            options={selectOptions}
                            value={option}
                            onChange={(opt) => setOption({ label: opt?.label ?? "", value: opt?.value ?? "multi", icon: opt?.icon })}
                            components={{
                                Option: CustomSearchOption,
                                SingleValue: CustomSingleValue
                            }}
                        />
                        <SearchWithHistory
                            onChange={setSearch}
                            value={search}
                            onSearch={(term) => executeSearch(term)}
                        />
                    </>
                }
            />
            <Container
                title={
                    hasSearched
                        ? isLoading
                            ? "Searching..."
                            : media.length > 0
                                ? "Search Results"
                                : "No Results Found"
                        : "Trending Today"
                }
                className="media-grid"
            >
                {
                    !hasSearched ? (

                        trendingTodayRow

                    ) : isLoading ? (

                        <div className="search-loading">
                            <Loader />
                        </div>

                    ) : media.length > 0 ? (

                        searchResultsRow

                    ) : (

                        <>
                            <div className="no-results">
                                <Icon Icon={FaSearch} />
                                <h2>No results found.</h2>
                                <p>Try searching something else.</p>
                            </div>

                            <Title
                                className="no-results-trending-today-title"
                                title="Browse Trending Today"
                            />

                            {trendingTodayRow}
                        </>
                    )
                }
            </Container>
        </div>
    )
}

export default Search;
