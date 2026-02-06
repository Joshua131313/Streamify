import { useRef, useState } from "react";
import { useSearchParams } from "react-router-dom";

import { Container } from "../../components/layout/Container/Container";
import { StyledSelect } from "../../components/ui/StyledSelect/StyledSelect";

import { TMDB_MEDIA_GENRES } from "../../data/TMDBGenres";
import type { TLabelValue } from "../../types/tmdb";

import { useInfiniteMediaBrowse } from "../../hooks/mediaHooks/useInfiniteMediaBrowse";
import { useInfiniteScroll } from "../../hooks/utilHooks/useInfiniteScroll";

import { MediaCard } from "../../components/ui/MediaCard/MediaCard";
import { MovieSeriesContainer } from "../../components/layout/Container/MovieSeriesContainer/MovieSeriesContainer";

import "./Browse.css";

export const Browse = () => {
  const [searchParams, setSearchParams] = useSearchParams();
  const mediaType = searchParams.get("media") ?? "movie";

  const [browseType, setBrowseType] = useState<TLabelValue>({
    value: "browse",
    label: "Browse",
  });

  const loadMoreRef = useRef<HTMLDivElement | null>(null);

  const { media, genre, fetchNextPage, hasNextPage } = useInfiniteMediaBrowse();

  useInfiniteScroll(loadMoreRef, fetchNextPage, !!hasNextPage);

  /** Update URL params */
  const setParam = (param: string, value: string) => {
    const params = new URLSearchParams(searchParams);
    value ? params.set(param, value) : params.delete(param);
    setSearchParams(params);
  };


  const isSeriesMode = mediaType === "movie" && browseType.value === "movie-series";

  return (
    <div className={`${mediaType === "movie" ? "movies-browse-page" : ""} browse-page`}>
      {/* Header + Controls */}
      <Container
        title={mediaType === "tv" ? "Browse TV Shows" : "Browse Movies"}
        className="browse"
        styled
      >
        <div className="browse-controls">
          {/* Genre filter */}
          <StyledSelect<TLabelValue, false>
            options={[{ value: "", label: "All" }, ...TMDB_MEDIA_GENRES]}
            value={genre}
            onChange={(opt) =>
              setParam("genre", opt?.value ?? "")
            }
          />

          {/* Movie-only browse type */}
          {mediaType === "movie" && (
            <StyledSelect<TLabelValue, false>
              options={[
                { value: "browse", label: "Browse" },
                { value: "movie-series", label: "Movie Series" },
              ]}
              value={browseType}
              onChange={(opt) =>
                setBrowseType({
                  value: opt?.value ?? "browse",
                  label: opt?.label ?? "Browse",
                })
              }
            />
          )}
        </div>
      </Container>

      {/* Content */}
      {isSeriesMode ? (
        <MovieSeriesContainer genre={Number(genre?.value) || undefined} />
      ) : (
        <Container className="browse-results media-grid">
          {media.map((m) => (
            <MediaCard key={m.id} media={m} />
          ))}
        </Container>
      )}

      {/* Infinite scroll trigger */}
      <div ref={loadMoreRef} style={{ height: 1 }} />
    </div>
  );
};
