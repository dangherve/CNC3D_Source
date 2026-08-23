/* ====================================================================================
 *  cnc_game.h -- what the application shell is allowed to know about the game.
 *
 *  cnc_eyes.cpp used to be a program: it parsed argv, opened a window, booted the
 *  brain, ran until you pressed ESC and then exited the process. In the shipping
 *  build the menu is what owns the program, and a mission is something that starts
 *  and ends inside a window that already existed and will still exist afterwards.
 *
 *  These five calls are that seam, and nothing else crosses it. The shell owns
 *  SDL, the window and the GL context; the game owns the brain, its packs and its
 *  frames while it is running, and hands every one of them back on the way out.
 *
 *      game_parse_args   argv -> GameOpts. Reads no files, opens nothing.
 *      game_boot         brain + packs + sidebar, into a window that exists.
 *      game_loop         run until the player leaves. Draws and swaps.
 *      game_shutdown     give back every texture and every allocation from boot.
 *
 *  boot -> loop -> shutdown may be repeated any number of times on one context.
 *  That is a tested property, not a hope: see harness.c.
 * ==================================================================================== */

#ifndef CNC_GAME_H
#define CNC_GAME_H

#include <SDL.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Everything the command line decides. Plain pointers into argv, which outlives
   the program, so nothing here owns memory. */
typedef struct GameOpts {
    const char* dylib;      /* NULL -> probe the usual places      */
    const char* dir;        /* mission directory                   */
    const char* content;    /* MIX directory                       */
    const char* scen;       /* SCG01EC and friends                 */
    const char* pack;       /* terrain/model pack; NULL -> scen.pack */
    const char* cam;        /* "X,Z" start position, or NULL       */
    const char* cameos;
    const char* dospack;
    const char* dosinf;     /* NULL = keep the N64 infantry        */
    const char* dosmake;    /* NULL = buildings pop in finished    */
    const char* efx;
    const char* dostib;     /* real tiberium art pack; missing = crystals  */
    const char* smudge;     /* scorch marks, craters, building aprons     */
    const char* verdict;    /* N64 MISSION ACCOMPLISHED/FAILED banners     */
    const char* shot;       /* headless PNG mode                   */
    const char* script;     /* headless script mode                */
    const char* posetest;
    /* Sound. Where the 1995 archives are, and where the mix comes out. */
    const char* dosdata;    /* SOUNDS.MIX and friends; NULL -> "dosdata"    */
    const char* audiowav;   /* record the mix to this WAV, open no device   */
    int nosound;            /* open nothing and make no noise               */
    int musicvol, soundvol; /* the 1995 Game Controls sliders, 0..255       */
    /* HARNESS ONLY (--flowtest): after this many ticks with no real verdict,
       synthesize a WIN game-over event so the post-mission flow (win movie,
       score, map, next briefing) can run hands-off. 0 in every real game. */
    int forcewin_ticks;
    int build;              /* build level                         */
    int ticks;              /* --ticks, warm-up for shot/script    */
    int w, h;               /* requested framebuffer size          */
    int dumpobj;
    int picktest;
    int radar_off;
    int radar_strict;
    int radar_force;   /* --forceradar: show the radar without a Comm Center (gates) */
} GameOpts;

/* Why game_loop came back. The shell decides what to do about it; the game does
   not call exit(). */
enum {
    GAME_EXIT_MENU = 0,     /* ESC, or --run elapsed: show the menu again */
    GAME_EXIT_APP = 1,      /* the window was closed: close the program   */
    GAME_EXIT_ERROR = 2,    /* the brain stopped advancing, or an assertion failed */
    GAME_EXIT_WON = 3,      /* the engine declared the mission won (game-over event) */
    GAME_EXIT_LOST = 4      /* the engine declared it lost */
};

/* The sound engine is owned by the PROGRAM, not by a mission: one bank and one
   device for the whole process, shared by the menu, the movies and the tactical
   view. The shell creates it (audio/audioboot.h) and lends it here, so a mission
   that starts and ends does not take the sound card with it. NULL is legal and
   means silence; every audio call in the renderer is a no-op then. */
struct CncAudio;
void game_set_audio(struct CncAudio* au);

int  game_parse_args(int argc, char** argv, GameOpts* out);   /* 0 ok, 2 usage printed */
int  game_boot(SDL_Window* win, const GameOpts* o);           /* 1 ok, 0 failed        */
int  game_loop(SDL_Window* win, const GameOpts* o);           /* GAME_EXIT_*           */
void game_shutdown(void);

/* The Visuals screen, run modally on the shell's own window. The main menu has no DOS
   pack and no 8-bit surface of its own, so it asks for the screen rather than building a
   second copy of it. Returns 1 if the window was closed while it was up. */
/* The main menu's Visuals screen. `shot`, when non-NULL, makes it a MEASURING
   INSTRUMENT rather than a screen: it draws exactly one frame, then takes the ordinary
   close path without a key being pressed. A non-empty string is also written out as a
   PNG; the EMPTY string means "one frame, close, write nothing", which is what a caller
   wants when it is after the screen's SIDE EFFECTS rather than its picture. NULL is the
   real screen, modal, waiting for a human -- never that in a headless run, or it hangs.
   That is what lets a gate assert both halves of this screen at once -- that it draws
   anything at all, and that closing it without touching a dial writes no preset.
   Before it existed the menu could not be driven headlessly in any way, which is
   precisely why the button stayed broken from 19 to with the suite green. */
int  game_visuals_open(SDL_Window* win, const char* dospack, const char* shot);

/* ---- save and load ------------------------------------------------------------------
   The engine writes the game (CNC_Save_Load -> saveload.cpp); these carry the handful of
   things it does not know it has -- the camera, which .pack the terrain came from, the
   campaign position and the music -- and re-sync the renderer across the discontinuity a
   load is. See game/dossave.h for the slot store. */
struct DS_Slot;
int  game_save_slot(int slot, const char* descr);   /* 1 ok */
int  game_load_slot(int slot);                      /* 1 ok */
int  game_slot_list(struct DS_Slot* out, int max);  /* -> count filled */
/* The campaign position lives in the shell, so it is handed down before a save and read
   back after a load. */
void game_set_campaign(int active, int side, int scenario, int dir, int var);
void game_get_campaign(int* active, int* side, int* scenario, int* dir, int* var);

/* ENHANCED BY DEFAULT, AND IT IS THE SHELL THAT DECIDES.
 *
 * A player launching the game gets the desktop picture and their own saved preset; the
 * measuring instrument does not. That split is the whole reason this is a call the SHELL
 * makes rather than a value in fx_defaults(): 71 of the gate suite's invocations drive
 * cnc_eyes and assert against the picture this project has always shipped, and three
 * drive cnc3d and assert state rather than pixels. Moving the default into the library
 * would have changed what all 71 of them measure.
 *
 * `preset` is loaded if it exists and ignored in silence if it does not, because a
 * first run has no saved config and that is not an error. */
void game_visuals_default_enhanced(const char* preset);

/* Headless modes, kept out of the shell: they are measuring instruments, and each
   one ends the process. Call after game_boot. */
int  game_run_picktest(const GameOpts* o);
int  game_run_script(SDL_Window* win, const GameOpts* o);
int  game_run_shot(SDL_Window* win, const GameOpts* o);

/* One tactical frame into the back buffer, no swap. The harness draws, reads the
   pixels back and only then swaps, which is the only way to be sure the PNG it
   writes is the frame it is talking about. */
void game_draw(SDL_Window* win);

/* The back buffer, as a PNG. Shared with the menu so both screens are proved with
   the same readback and the same writer. Returns 1 on success. */
int  game_grab_png(const char* path, int w, int h);

/* What the engine's game-over event said, valid after game_loop returns
   GAME_EXIT_WON or GAME_EXIT_LOST: the win/lose movie name (no extension) and the
   engine's own single-player score payload (Calculate_Single_Player_Score). */
typedef struct GameOverInfo {
    int  valid, win;
    char movie[16];
    int  score, leadership, efficiency;
    int  nod_killed, gdi_killed, civ_killed;
    int  nod_bldg, gdi_bldg, civ_bldg;
    int  credits;
    /* Elapsed mission time in whole minutes, for the score screen's TIME field.
       The DLL's GameOverEvent does not carry it, so we derive it the way 1995 does:
       conquer.cpp:1684 adds 4 to Score.ElapsedTime once per game frame, and
       score.cpp:659 prints ElapsedTime / TIMER_MINUTE (3600) + 1. cnc_eyes runs the
       brain at TICK_HZ 15, one engine tick per game frame, so
       minutes = ticks * 4 / 3600 + 1 = ticks / 900 + 1. */
    int  minutes;
} GameOverInfo;
const GameOverInfo* game_over_info(void);

#ifdef __cplusplus
}
#endif

#endif /* CNC_GAME_H */
