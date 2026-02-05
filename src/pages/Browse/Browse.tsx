import { Container } from "../../components/layout/Container/Container"
import { TMDB_MEDIA_GENRES } from "../../data/TMDBGenres"
import { useRef, useState } from "react"
import type { TMediaType, TLabelValue } from "../../types/tmdb"
import { useNavigate, useSearchParams } from "react-router-dom"
import { StyledSelect } from "../../components/ui/StyledSelect/StyledSelect"
import { useMediaBrowse } from "../../hooks/mediaHooks/useMediaBrowse"
import { ORDER_BY_OPTIONS } from "../../data"
import { MediaCard } from "../../components/ui/MediaCard/MediaCard"
import { useInfiniteScroll } from "../../hooks/utilHooks/useInfiniteScroll"
import { useInfiniteMediaBrowse } from "../../hooks/mediaHooks/useInfiniteMediaBrowse"
import "./Browse.css"

export const Browse = () => {
    const [searchParams, setSearchParams] = useSearchParams();
    const [page, setPage] = useState(1);
    const mediaType = searchParams.get("media");
    const loadMoreRef = useRef<HTMLDivElement | null>(null);
    const { media, genre, fetchNextPage, hasNextPage, isFetchingNextPage } = useInfiniteMediaBrowse();

    const mediaRow = media.map(m => {
        return (
            <MediaCard media={m} />
        )
    })

    const addParams = (param : string, value: string) => {
        const params = new URLSearchParams(searchParams);
        if(value) {
            params.set(param, value);
        }
        else {
            params.delete(param)
        }
        setSearchParams(params)
    }

    const genreChange = (opt : TLabelValue) => {
        addParams("genre", opt.value);
    }
    // const orderByChange = (opt : TLabelValue) => {
    //     addParams("orderBy", opt.value);
    // }
    useInfiniteScroll(loadMoreRef, fetchNextPage, !!hasNextPage);

    return (
        <>
        <Container title={mediaType === "tv" ? "TV Shows" : "Movies"} className="browse">
            <div className="browse-controls">
                <StyledSelect<TLabelValue, false> 
                    options={[{value: "", label: "All"}, ...TMDB_MEDIA_GENRES]}
                    value={genre}
                    onChange={(opt) => genreChange({label: opt?.label ?? "", value: opt?.value ?? ""})}
                />
                {/* <StyledSelect<TLabelValue, false> 
                    options={ORDER_BY_OPTIONS}
                    value={orderBy}
                    onChange={(opt) => orderByChange({label: opt?.label ?? "", value: opt?.value ?? ""})}
                /> */}
            </div>

        </Container>            
        <Container className="browse-results media-grid">
            {mediaRow}
        </Container>
        <div className="load-more" ref={loadMoreRef} style={{ height: 1}}></div>
        </>
    )
}