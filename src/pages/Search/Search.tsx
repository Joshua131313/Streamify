import { useMemo, useState } from "react"
import { Container } from "../../components/layout/Container/Container"
import { MediaCard } from "../../components/ui/MediaCard/MediaCard"
import { StyledSelect } from "../../components/ui/StyledSelect/StyledSelect"
import { useMixedMedia } from "../../hooks/mediaHooks/useMixedMedia"
import "./Search.css"
import { Input } from "../../components/ui/Input/Input"
import { FaSearch } from "react-icons/fa"
import { useTMDBQuery } from "../../hooks/mediaHooks/tmdbHooks/useTMDBQuery"
import { normalizeTMDBMedia } from "../../utils/normalizeTMDB"
import { useSearchMedia } from "../../hooks/mediaHooks/useSearchMedia"
import type { TMediaType } from "../../types/tmdb"
import { PageHeader } from "../../components/ui/PageHeader/PageHeader"
export type Option = {
    value: TMediaType | "multi";
    label: string;
};
export const selectOptions : Option[] = [
    {
        value: "multi",
        label: "All",
    },
    {
        value: "movie",
        label: "Movies"
    },
    {
        value: "tv",
        label: "TV Shows"
    }

]
export const Search = () => {

    const { media: trendingToday} = useMixedMedia("/trending/all/day", 20);
    const [option, setOption] = useState<Option>(selectOptions[0]);
    const { executeSearch, setSearch, search, media } = useSearchMedia(option.value);
    const trendingTodayRow = trendingToday.map(media => {
        return (
            <MediaCard media={media} key={media.id}/>
        )
    })
    const searchResultsRow = media.map(media => {
        return (
            <MediaCard media={media} key={media.id}/>
        )
    })

    return (
        <div className="search-page">
            <PageHeader 
                title="Browse Through The Catalog"
                subTitle="Search through thousands of movies, TV shows and anime series"
                controls={
                    <>
                        <StyledSelect<Option, false> 
                            options={selectOptions}
                            value={option}
                            onChange={(opt) => setOption({label: opt?.label ?? "", value: opt?.value ?? "multi"})}
                        />
                        <Input 
                            autoFocus
                            Icon={FaSearch}
                            placeholder="Type here to search"
                            value={search}
                            onChange={(e) => setSearch(e.target.value)}
                            onKeyDown={(e) => e.key === "Enter" && executeSearch()}
                        />
                    </>
                }
            />
            {/* <Container className="search-container">
                <div className="search-title">
                    <h1>Browse Through The Catalog</h1>
                    <span>Search through thousands of movies, TV shows and anime series</span>
                </div>
                <Container className="search-controls" styled>
                    <StyledSelect<Option, false> 
                        options={selectOptions}
                        value={option}
                        onChange={(opt) => setOption({label: opt?.label ?? "", value: opt?.value ?? "multi"})}
                    />
                    <Input 
                        autoFocus
                        Icon={FaSearch}
                        placeholder="Type here to search"
                        value={search}
                        onChange={(e) => setSearch(e.target.value)}
                        onKeyDown={(e) => e.key === "Enter" && executeSearch()}
                    />
                </Container>
            </Container> */}
            <Container title={searchResultsRow.length ? "Search Results" : "Trending Today"} className="media-grid">
                {
                    searchResultsRow.length ? 
                    searchResultsRow :
                    trendingTodayRow
                }
            </Container>
        </div>
    )
}