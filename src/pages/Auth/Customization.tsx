import { useMemo, useState } from "react";
import { Button } from "../../components/ui/Button/Button";
import { useNavigate } from "react-router-dom";
import { Container } from "../../components/layout/Container/Container";

import { TMDB_GENRES } from "../../data/TMDBGenres";
import { nbaTeamsMap } from "../../data/sports/nbaData";
import { nhlTeamsMap } from "../../data/sports/nhlData";
import { mlbTeamsMap } from "../../data/sports/mlbData";

type Step = "movies" | "sports";

type TeamInfo = {
  abbreviation: string;
  teamName: string;
  id: string;
  conference?: string;
  division?: string;
  league: string;
};

type TeamsMap = Record<string, TeamInfo>;

type TeamPickerProps = {
  title: string;
  teamsMap: TeamsMap;
  selectedTeams: string[];
  onToggle: (teamId: string) => void;
};

const TeamPickerSection = ({
  title,
  teamsMap,
  selectedTeams,
  onToggle,
}: TeamPickerProps) => {
  const teams = Object.values(teamsMap);

  return (
    <div className="team-section">
      <h3>{title}</h3>

      <div className="team-grid">
        {teams.map((team) => {
          const selected = selectedTeams.includes(team.id);

          return (
            <button
              key={team.id}
              type="button"
              className={`team-card ${selected ? "selected" : ""}`}
              onClick={() => onToggle(team.id)}
            >
              <div className="team-league">{team.league}</div>
              <div className="team-abbr">{team.abbreviation}</div>
              <div className="team-name">{team.teamName}</div>
              {team.division && (
                <div className="team-meta">{team.division}</div>
              )}
            </button>
          );
        })}
      </div>
    </div>
  );
};

export const Customization = () => {
  const navigate = useNavigate();

  const [step, setStep] = useState<Step>("movies");

  const [selectedGenres, setSelectedGenres] = useState<string[]>([]);
  const [selectedTeams, setSelectedTeams] = useState<string[]>([]);

  const [error, setError] = useState("");

  const allSportsMaps = useMemo(
    () => [
      { title: "NBA", map: nbaTeamsMap },
      { title: "NHL", map: nhlTeamsMap },
      { title: "MLB", map: mlbTeamsMap },
    ],
    []
  );

  const toggleGenre = (genre: string) => {
    setSelectedGenres((prev) =>
      prev.includes(genre)
        ? prev.filter((g) => g !== genre)
        : [...prev, genre]
    );
  };

  const toggleTeam = (teamId: string) => {
    setSelectedTeams((prev) =>
      prev.includes(teamId)
        ? prev.filter((t) => t !== teamId)
        : [...prev, teamId]
    );
  };

  const handleSkip = () => {
    navigate("/");
  };

  const handleContinueMovies = () => {
    setError("");

    if (selectedGenres.length === 0) {
      setError("Select at least one genre");
      return;
    }

    setStep("sports");
  };

  const handleFinish = async () => {
    setError("");

    try {
      // await updateUserPreferences(...)
      navigate("/");
    } catch {
      setError("Failed to save preferences");
    }
  };

  return (
    <Container className="auth customization" styled>
      <h1>Customize Your Experience</h1>

      <div className="step-indicator">
        <div className={`step-pill ${step === "movies" ? "active" : "done"}`}>
          Movies
        </div>
        <div className={`step-pill ${step === "sports" ? "active" : ""}`}>
          Sports
        </div>
      </div>

      {step === "movies" && (
        <>
          <div className="section">
            <h2>Select Favorite Genres</h2>
            <p>Choose a few genres to personalize recommendations.</p>

            <div className="genre-grid">
              {TMDB_GENRES.map((genre) => {
                const selected = selectedGenres.includes(genre.value);

                return (
                  <button
                    key={genre.value}
                    type="button"
                    className={`genre-chip ${selected ? "selected" : ""}`}
                    onClick={() => toggleGenre(genre.value)}
                  >
                    {genre.label}
                  </button>
                );
              })}
            </div>
          </div>

          {error && <p className="error">{error}</p>}

          <div className="controls">
            <Button className="secondary" onClick={handleSkip}>
              Skip
            </Button>

            <Button onClick={handleContinueMovies}>
              Continue
            </Button>
          </div>
        </>
      )}

      {step === "sports" && (
        <>
          <div className="section">
            <h2>Select Favorite Teams</h2>
            <p>Pick teams you want followed across leagues.</p>

            {allSportsMaps.map((league) => (
              <TeamPickerSection
                key={league.title}
                title={league.title}
                teamsMap={league.map}
                selectedTeams={selectedTeams}
                onToggle={toggleTeam}
              />
            ))}
          </div>

          {error && <p className="error">{error}</p>}

          <div className="controls">
            <Button
              className="secondary"
              onClick={() => setStep("movies")}
            >
              Back
            </Button>

            <Button onClick={handleFinish}>
              Finish
            </Button>
          </div>
        </>
      )}
    </Container>
  );
};