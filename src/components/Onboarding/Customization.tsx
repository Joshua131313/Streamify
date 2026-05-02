import { useState } from "react";
import { Button } from "../ui/Button/Button";
import { useNavigate } from "react-router-dom";
import { Container } from "../layout/Container/Container";

import { TMDB_GENRES } from "../../data/TMDBGenres";
import { nbaTeamsMap } from "../../data/sports/nbaData";
import { nhlTeamsMap } from "../../data/sports/nhlData";
import { mlbTeamsMap } from "../../data/sports/mlbData";
import { AppImg } from "../ui/ImgProxy/AppImg";
import { getTeamLogo } from "../../utils/sports/sportsUtils";
import type { TeamInfo } from "../../types/sports/sportsTypes";
import {  FaChevronRight } from "react-icons/fa";
import {  BsCheckCircleFill, BsCircle } from "react-icons/bs";
import { addFavoriteGenres, addTeamsToFavorites, completeOnboarding } from "../../firebase/auth";
import { useAuthProvider } from "../../context/AuthContext";
import "./Onboarding.css"

type Step = "movies" | "nba" | "mlb" | "nhl";

type TeamsMap = Record<string, TeamInfo>;

type TeamPickerProps = {
  title: string;
  teamsMap: TeamsMap;
  selectedTeams: TeamInfo[];
  onToggle: (team: TeamInfo) => void;
};

const SportsTab = ({
  teamsMap,
  title,
  selectedTeams,
  onToggle,
}: TeamPickerProps) => {
  return (
    <div className="section">
      <TeamPickerSection
        key={title}
        title={title}
        teamsMap={teamsMap}
        selectedTeams={selectedTeams}
        onToggle={onToggle}
      />
    </div>
  )
}


const TeamPickerSection = ({
  title,
  teamsMap,
  selectedTeams,
  onToggle,
}: TeamPickerProps) => {
  const teams = Object.values(teamsMap);

  return (
    <Container title={title} className="team-section">
      <div className="team-grid">
        {teams.map((team) => {
          const selected = selectedTeams.some(x => x.id === team.id);

          return (
            <div key={team.id} onClick={() => onToggle(team)} className={`team-card ${selected ? "selected" : ""}`}>
              <AppImg src={getTeamLogo(team.league, team.abbreviation)} />
              <div className="team-name">{team.teamName}</div>
              {
                selectedTeams.some(x => x.id === team.id) ?
                  <BsCheckCircleFill /> :
                  <BsCircle />
              }
            </div>
          );
        })}
      </div>
    </Container>
  );
};

interface Props {
  onClose: () => void;
}

export const Customization = (props: Props) => {
  const { onClose } = props;
  const navigate = useNavigate();
  const { userData, user, loading } = useAuthProvider();
  const [step, setStep] = useState<Step>("movies");
  const [onboardingLoading, setOnboardingLoading] = useState(false);
  const [selectedGenres, setSelectedGenres] = useState<string[]>([]);
  const [selectedTeams, setSelectedTeams] = useState<TeamInfo[]>([]);

  const [error, setError] = useState("");

  const toggleGenre = (genre: string) => {
    setSelectedGenres((prev) =>
      prev.includes(genre)
        ? prev.filter((g) => g !== genre)
        : [...prev, genre]
    );
  };

  const toggleTeam = (team: TeamInfo) => {
    setSelectedTeams((prev) =>
      prev.some(x => x.id === team.id)
        ? prev.filter((t) => t.id !== team.id)
        : [...prev, team]
    );
  };

  const handleSkip = () => {
    setError("")
    setOnboardingLoading(true);
    try {
      completeOnboarding();
    }
    catch {
      setError("Error completing onboarding")
    }
    finally {
      setOnboardingLoading(false);
      onClose();
    }
  };

  const handleContinue = () => {
    if (step === "movies") {
      setStep("nba")
      return;
    }
    switch (step) {
      case "nba":
        setStep("nhl");
        break;
      case "nhl":
        setStep("mlb");
        break;
      case "mlb":
        handleFinish();
    }
  }

  const handleBack = () => {
    switch (step) {
      case "nba":
        setStep("movies");
        break;
      case "nhl":
        setStep("nba");
        break;
      case "mlb":
        setStep("nhl")
    }
  }
  const handleFinish = async () => {
    setError("");
    setOnboardingLoading(true);

    try {
      await addFavoriteGenres(selectedGenres);
      await addTeamsToFavorites(selectedTeams);
      await completeOnboarding();

      onClose();
    } catch (error) {
      setError("Failed to save preferences");
    } finally {
      setOnboardingLoading(false);
    }
  };
  
  return (
    <Container className="customization" styled>
      <div className="step-indicator">
        <strong>Complete onboarding</strong>
        <div className="steps">
          <div onClick={() => setStep("movies")} className={`step-pill ${step === "movies" ? "active" : "done"}`}>
            Movies
          </div>
          <FaChevronRight />
          <div onClick={() => setStep("nba")} className={`step-pill ${step === "nba" ? "active" : ""}`}>
            NBA
          </div>
          <FaChevronRight />
          <div onClick={() => setStep("nhl")} className={`step-pill ${step === "nhl" ? "active" : ""}`}>
            NHL
          </div>
          <FaChevronRight />
          <div onClick={() => setStep("mlb")} className={`step-pill ${step === "mlb" ? "active" : ""}`}>
            MLB
          </div>
        </div>
      </div>
      <div className="inner-customization">
        {step === "movies" && (
          <>
            <Container title="Select Favorite Genres" className="section">
              <div className="genre-grid">
                {TMDB_GENRES.map((genre) => {
                  const selected = selectedGenres.includes(genre.value);

                  return (
                    <div
                      key={genre.value}
                      className={`genre-chip ${selected ? "selected" : ""}`}
                      onClick={() => toggleGenre(genre.value)}
                    >
                      {genre.label}
                      {
                        selectedGenres.includes(genre.value) ?
                          <BsCheckCircleFill /> :
                          <BsCircle />
                      }
                    </div>
                  );
                })}
              </div>
            </Container>
          </>
        )}

        {step === "nba" && (
          <>
            <SportsTab
              onToggle={toggleTeam}
              selectedTeams={selectedTeams}
              teamsMap={nbaTeamsMap}
              title="Follow NBA Teams"
            />

          </>
        )}
        {step === "nhl" && (
          <>
            <SportsTab
              onToggle={toggleTeam}
              selectedTeams={selectedTeams}
              teamsMap={nhlTeamsMap}
              title="Follow NHL Teams"
            />

          </>
        )}
        {step === "mlb" && (
          <>
            <SportsTab
              onToggle={toggleTeam}
              selectedTeams={selectedTeams}
              teamsMap={mlbTeamsMap}
              title="Follow MLB Teams"
            />

          </>
        )}
        {error && <p className="error">{error}</p>}
      </div>

      <div className="controls">
        {
          step !== "movies" ?
            <Button className="secondary" onClick={handleBack}>
              Back
            </Button>
            : <div></div>
        }

        <div className="right-controls">
          <Button className="secondary" onClick={handleSkip}>
            Skip onboarding
          </Button>
          <Button onClick={handleContinue} loading={onboardingLoading}>
            {
              step === "mlb" ?
                "Finish" : "Next"
            }
          </Button>
        </div>
      </div>
    </Container>
  );
};