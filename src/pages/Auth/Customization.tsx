import { useState } from "react";
import { Button } from "../../components/ui/Button/Button";
import { useAuthProvider } from "../../context/AuthContext";
import { useNavigate } from "react-router-dom";
import { Auth } from "./Auth";
import { Container } from "../../components/layout/Container/Container";

const TEAMS = [
  "Lakers",
  "Warriors",
  "Celtics",
  "Canadiens",
  "Maple Leafs",
  "Yankees",
];

const GENRES = [
  "Action",
  "Comedy",
  "Drama",
  "Horror",
  "Sci-Fi",
  "Documentary",
];

export const Customization = () => {
  const [selectedTeams, setSelectedTeams] = useState<string[]>([]);
  const [selectedGenres, setSelectedGenres] = useState<string[]>([]);
  const [error, setError] = useState("");

  const { user } = useAuthProvider();
  const navigate = useNavigate();

  const toggleTeam = (team: string) => {
    setSelectedTeams((prev) =>
      prev.includes(team)
        ? prev.filter((t) => t !== team)
        : [...prev, team]
    );
  };

  const toggleGenre = (genre: string) => {
    setSelectedGenres((prev) =>
      prev.includes(genre)
        ? prev.filter((g) => g !== genre)
        : [...prev, genre]
    );
  };

  const handleSubmit = async () => {
    if (selectedTeams.length === 0) {
      setError("Select at least one team");
      return;
    }

    if (selectedGenres.length === 0) {
      setError("Select at least one genre");
      return;
    }

    try {
    //   await updateUserPreferences(user.uid, {
    //     favoriteTeams: selectedTeams,
    //     favoriteGenres: selectedGenres,
    //   });

      navigate("/");
    } catch (err) {
      setError("Failed to save preferences");
    }
  };

  return (
    <>
    <Container className="auth" styled>
         <h1>Customize Your Experience</h1>

      {/* Teams */}
      <div className="section">
        <h2>Favorite Teams</h2>
        <div className="options">
          {TEAMS.map((team) => (
            <div
              key={team}
              className={`option ${
                selectedTeams.includes(team) ? "selected" : ""
              }`}
              onClick={() => toggleTeam(team)}
            >
              {team}
            </div>
          ))}
        </div>
      </div>

      {/* Genres */}
      <div className="section">
        <h2>Favorite Genres</h2>
        <div className="options">
          {GENRES.map((genre) => (
            <div
              key={genre}
              className={`option ${
                selectedGenres.includes(genre) ? "selected" : ""
              }`}
              onClick={() => toggleGenre(genre)}
            >
              {genre}
            </div>
          ))}
        </div>
      </div>

      {error && <p className="error">{error}</p>}

      <Button onClick={handleSubmit}>
        Continue
      </Button>
    </Container>
    <Auth title="Customization" type="register" childrenContainerClassName="" header={{title: "asd", link: {label: " as", to: "asd"}}} onSubmit={() => {}}>
      <h1>Customize Your Experience</h1>

      {/* Teams */}
      <div className="section">
        <h2>Favorite Teams</h2>
        <div className="options">
          {TEAMS.map((team) => (
            <div
              key={team}
              className={`option ${
                selectedTeams.includes(team) ? "selected" : ""
              }`}
              onClick={() => toggleTeam(team)}
            >
              {team}
            </div>
          ))}
        </div>
      </div>

      {/* Genres */}
      <div className="section">
        <h2>Favorite Genres</h2>
        <div className="options">
          {GENRES.map((genre) => (
            <div
              key={genre}
              className={`option ${
                selectedGenres.includes(genre) ? "selected" : ""
              }`}
              onClick={() => toggleGenre(genre)}
            >
              {genre}
            </div>
          ))}
        </div>
      </div>

      {error && <p className="error">{error}</p>}

      <Button onClick={handleSubmit}>
        Continue
      </Button>
    </Auth></>
  );
};