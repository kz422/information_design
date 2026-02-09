ArrayList<Quake> quakes;
ArrayList<Ripple> ripples;
ArrayList<Crack> cracks;
ArrayList<Particle> particles;
ArrayList<Flash> flashes;
ArrayList<float[]> worldPolygons;

// 画面マージン
float MARGIN_X = 30;
float MARGIN_TOP = 60;
float MARGIN_BOTTOM = 40;

int currentYear = 2026;
boolean loading = false;
String statusMsg = "";
float shakeAmount = 0;
float shakeDecay = 0.92;

// スレッド間データ受け渡し用
volatile ArrayList<Quake> loadedQuakes = null;
volatile String loadedStatusMsg = null;

// 自動再生用の変数
ArrayList<Quake> pendingQuakes;
int autoPlayIndex = 0;
int autoPlayLastMs = 0;
int autoPlayIntervalMs = 300; // ミリ秒間隔
boolean autoPlaying = false;

// エフェクト上限
int MAX_RIPPLES = 80;
int MAX_CRACKS = 60;
int MAX_PARTICLES = 300;
int MAX_FLASHES = 30;

void setup() {
  size(1000, 600);
  pixelDensity(1);
  quakes = new ArrayList<Quake>();
  ripples = new ArrayList<Ripple>();
  cracks = new ArrayList<Crack>();
  particles = new ArrayList<Particle>();
  flashes = new ArrayList<Flash>();
  pendingQuakes = new ArrayList<Quake>();
  worldPolygons = new ArrayList<float[]>();
  textFont(createFont("SansSerif", 14));
  loadWorldMap();
  fetchYear(currentYear);
}

color quakeColor(int value) {
  float t = constrain(map(value, 1, 8, 0, 1), 0, 1);
  if (t < 0.5) {
    float s = t * 2;
    return color(lerp(40, 255, s), lerp(160, 220, s), lerp(220, 50, s));
  } else {
    float s = (t - 0.5) * 2;
    return color(255, lerp(220, 60, s), lerp(50, 20, s));
  }
}

// --- USGS API データ取得 ---
void fetchYear(int year) {
  statusMsg = year + "年 読み込み中...";
  loading = true;
  thread("loadData");
}

void loadData() {
  String url = "https://earthquake.usgs.gov/fdsnws/event/1/query?format=geojson"
    + "&starttime=" + currentYear + "-01-01"
    + "&endtime=" + currentYear + "-12-31"
    + "&minmagnitude=5&orderby=time-asc&limit=5000";
  try {
    JSONObject json = loadJSONObject(url);
    JSONArray features = json.getJSONArray("features");
    ArrayList<Quake> tempQuakes = new ArrayList<Quake>();
    for (int i = 0; i < features.size(); i++) {
      JSONObject f = features.getJSONObject(i);
      JSONObject props = f.getJSONObject("properties");
      JSONArray coords = f.getJSONObject("geometry").getJSONArray("coordinates");
      float lon = coords.getFloat(0);
      float lat = coords.getFloat(1);
      float mag = props.getFloat("mag");
      String place = props.getString("place");
      long timeMs = props.getLong("time");
      java.util.Calendar cal = java.util.Calendar.getInstance();
      cal.setTimeInMillis(timeMs);
      int month = cal.get(java.util.Calendar.MONTH) + 1; // 0-based → 1-based
      float sx = gx(lon);
      float sy = gy(lat);
      int value = constrain((int)map(mag, 5, 9, 1, 8), 1, 8);
      tempQuakes.add(new Quake(sx, sy, value, mag, place, month));
    }
    loadedQuakes = tempQuakes;
    loadedStatusMsg = currentYear + "年 : " + tempQuakes.size() + "件の地震 (M5以上)";
  }
  catch (Exception e) {
    loadedStatusMsg = "エラー: " + e.getMessage();
  }
  loading = false;
}

void draw() {
  // バックグラウンドスレッドからデータを受け取る
  if (loadedQuakes != null) {
    quakes = loadedQuakes;
    loadedQuakes = null;
    startAutoPlay();
  }
  if (loadedStatusMsg != null) {
    statusMsg = loadedStatusMsg;
    loadedStatusMsg = null;
  }

  pushMatrix();
  if (shakeAmount > 0.5) {
    translate(random(-shakeAmount, shakeAmount), random(-shakeAmount, shakeAmount));
    shakeAmount *= shakeDecay;
  } else {
    shakeAmount = 0;
  }

  background(15, 15, 20);
  drawWorldGrid();

  for (int i = flashes.size() - 1; i >= 0; i--) {
    Flash f = flashes.get(i);
    f.update();
    f.display();
    if (f.isDead()) flashes.remove(i);
  }
  for (int i = cracks.size() - 1; i >= 0; i--) {
    Crack c = cracks.get(i);
    c.update();
    c.display();
    if (c.isDead()) cracks.remove(i);
  }
  for (int i = ripples.size() - 1; i >= 0; i--) {
    Ripple r = ripples.get(i);
    r.update();
    r.display();
    if (r.isDead()) ripples.remove(i);
  }
  for (int i = particles.size() - 1; i >= 0; i--) {
    Particle p = particles.get(i);
    p.update();
    p.display();
    if (p.isDead()) particles.remove(i);
  }

  for (Quake q : quakes) {
    q.update();
    q.display();
  }

  // 自動再生の実行処理（millis()ベースでフレーム落ちに影響されない）
  if (autoPlaying && autoPlayIndex < pendingQuakes.size()) {
    int now = millis();
    while (autoPlayIndex < pendingQuakes.size() && now - autoPlayLastMs >= autoPlayIntervalMs) {
      triggerQuake(pendingQuakes.get(autoPlayIndex));
      autoPlayIndex++;
      autoPlayLastMs += autoPlayIntervalMs;
    }
  } else if (autoPlaying && autoPlayIndex >= pendingQuakes.size()) {
    autoPlaying = false;
  }

  popMatrix();
  drawUI();
}

float gx(float lon) {
  return map(lon, -180, 180, MARGIN_X, width - MARGIN_X);
}
float gy(float lat) {
  return map(lat, 90, -90, MARGIN_TOP, height - MARGIN_BOTTOM);
}

void loadWorldMap() {
  try {
    String url = "https://raw.githubusercontent.com/nvkelso/natural-earth-vector/master/geojson/ne_110m_land.geojson";
    JSONObject json = loadJSONObject(url);
    JSONArray features = json.getJSONArray("features");
    for (int i = 0; i < features.size(); i++) {
      JSONObject geom = features.getJSONObject(i).getJSONObject("geometry");
      String type = geom.getString("type");
      if (type.equals("Polygon")) {
        addRing(geom.getJSONArray("coordinates").getJSONArray(0));
      } else if (type.equals("MultiPolygon")) {
        JSONArray polys = geom.getJSONArray("coordinates");
        for (int j = 0; j < polys.size(); j++) {
          addRing(polys.getJSONArray(j).getJSONArray(0));
        }
      }
    }
    println("World map loaded: " + worldPolygons.size() + " polygons");
  }
  catch (Exception e) {
    println("Map load error: " + e.getMessage());
  }
}

void addRing(JSONArray ring) {
  float[] coords = new float[ring.size() * 2];
  for (int i = 0; i < ring.size(); i++) {
    JSONArray p = ring.getJSONArray(i);
    coords[i*2] = p.getFloat(0);
    coords[i*2+1] = p.getFloat(1);
  }
  worldPolygons.add(coords);
}

void drawWorldGrid() {
  // グリッド
  stroke(30, 30, 40);
  strokeWeight(0.5);
  for (float lon=-180; lon<=180; lon+=30) line(gx(lon), MARGIN_TOP, gx(lon), height - MARGIN_BOTTOM);
  for (float lat=-90; lat<=90; lat+=30) line(MARGIN_X, gy(lat), width - MARGIN_X, gy(lat));
  stroke(40, 40, 55);
  line(MARGIN_X, gy(0), width - MARGIN_X, gy(0));

  // 世界地図ポリゴン
  stroke(50, 58, 70);
  strokeWeight(0.8);
  noFill();
  for (float[] coords : worldPolygons) {
    beginShape();
    for (int i = 0; i < coords.length; i += 2) {
      vertex(gx(coords[i]), gy(coords[i+1]));
    }
    endShape(CLOSE);
  }
}

void drawUI() {
  // ヘッダー
  noStroke();
  fill(15, 15, 20, 200);
  rect(0, 0, width, 50);

  fill(255);
  textAlign(LEFT, CENTER);
  textSize(14);
  text(statusMsg, 20, 25);

  textAlign(CENTER, CENTER);
  textSize(22);
  fill(255);
  text("< " + currentYear + "年 >", width/2, 25);

  textAlign(RIGHT, CENTER);
  textSize(11);
  fill(150);
  text("[←/→] 年変更  [SPACE] 再生  [クリック] 地震エフェクト", width - 20, 25);

  // 進捗バー
  if (autoPlaying && pendingQuakes.size() > 0) {
    float prog = (float)autoPlayIndex / pendingQuakes.size();
    noStroke();
    float barY = 52;
    float barH = 4;
    float barW = width - MARGIN_X * 2;
    fill(50);
    rect(MARGIN_X, barY, barW, barH);
    fill(quakeColor(4));
    rect(MARGIN_X, barY, barW * prog, barH);

    // 各月の開始インデックスを計算（データに基づく実位置）
    String[] monthNames = {"1月","2月","3月","4月","5月","6月","7月","8月","9月","10月","11月","12月"};
    int total = pendingQuakes.size();
    int[] monthStart = new int[13]; // monthStart[m] = m月の最初のインデックス (1-12), [0]未使用
    for (int m = 0; m < 13; m++) monthStart[m] = -1;
    for (int i = 0; i < total; i++) {
      int m = pendingQuakes.get(i).month;
      if (monthStart[m] == -1) monthStart[m] = i;
    }

    // 月ラベルと区切り線（データに存在する月のみ）
    textSize(9);
    for (int m = 1; m <= 12; m++) {
      if (monthStart[m] == -1) continue; // この月のデータなし
      float startX = MARGIN_X + barW * ((float)monthStart[m] / total);
      // 月の終了位置を計算（次の月の開始 or 末尾）
      float endX;
      int nextStart = total;
      for (int nm = m + 1; nm <= 12; nm++) {
        if (monthStart[nm] != -1) { nextStart = monthStart[nm]; break; }
      }
      endX = MARGIN_X + barW * ((float)nextStart / total);
      float centerX = (startX + endX) / 2.0;

      // 区切り線（最初の月以外）
      if (monthStart[m] > 0) {
        stroke(80);
        strokeWeight(0.5);
        line(startX, barY, startX, barY + barH);
      }
      // ラベル（幅が十分あれば表示）
      fill(80);
      noStroke();
      textAlign(CENTER, TOP);
      if (endX - startX > textWidth(monthNames[m-1]) + 2) {
        text(monthNames[m-1], centerX, barY + barH + 2);
      }
    }

    // 現在再生中の月を強調表示
    if (autoPlayIndex > 0 && autoPlayIndex <= total) {
      int curMonth = pendingQuakes.get(autoPlayIndex - 1).month;
      fill(255);
      textSize(11);
      textAlign(LEFT, TOP);
      text(monthNames[curMonth - 1], MARGIN_X + barW * prog + 4, barY + barH + 1);
    }
  }
}

void keyPressed() {
  if (loading) return;
  if (keyCode == RIGHT) {
    currentYear++;
    clearEffects();
    fetchYear(currentYear);
  } else if (keyCode == LEFT) {
    currentYear--;
    clearEffects();
    fetchYear(currentYear);
  } else if (key == ' ') {
    clearEffects();
    startAutoPlay();
  }
}

void mousePressed() {
  for (Quake q : quakes) {
    if (q.isHovered(mouseX, mouseY)) {
      triggerQuake(q);
      return;
    }
  }
}

void clearEffects() {
  ripples.clear();
  cracks.clear();
  particles.clear();
  flashes.clear();
  autoPlaying = false;
}

// 自動再生の開始・リセット
void startAutoPlay() {
  pendingQuakes = new ArrayList<Quake>(quakes);
  autoPlayIndex = 0;
  autoPlayLastMs = millis();
  // 件数に応じて再生速度を調整（多い年は速く、30秒で全件再生を目安に）
  autoPlayIntervalMs = max(10, 30000 / max(1, pendingQuakes.size()));
  autoPlaying = true;
}

void triggerQuake(Quake o) {
  int v = o.value;
  color c = quakeColor(v);
  shakeAmount = map(v, 1, 8, 1, 20);
  o.tremor = map(v, 1, 8, 2, 12);
  o.highlight = 1.0;

  int rc = (int)map(v, 1, 8, 2, 7);
  for (int i = 0; i < rc && ripples.size() < MAX_RIPPLES; i++)
    ripples.add(new Ripple(o.x, o.y, v, c, i * map(v, 1, 8, 10, 5)));
  if (v >= 4) {
    int cc = (int)map(v, 4, 8, 2, 10);
    for (int i=0; i<cc && cracks.size() < MAX_CRACKS; i++)
      cracks.add(new Crack(o.x, o.y, v, c));
  }
  int pc = (int)map(v, 1, 8, 3, 40);
  for (int i = 0; i < pc && particles.size() < MAX_PARTICLES; i++)
    particles.add(new Particle(o.x, o.y, v, c));
  if (v >= 3 && flashes.size() < MAX_FLASHES)
    flashes.add(new Flash(o.x, o.y, v, c));
}

// ============================================================
class Quake {
  float x, y;
  int value;
  float mag;
  String place;
  int month; // 1-12
  float radius;
  float tremor = 0;
  float tremorDecay = 0.9;
  float highlight = 0;

  Quake(float x, float y, int value, float mag, String place, int month) {
    this.x = x;
    this.y = y;
    this.value = value;
    this.mag = mag;
    this.place = place;
    this.month = month;
    this.radius = map(value, 1, 8, 4, 14);
  }

  void update() {
    if (tremor > 0.2) tremor *= tremorDecay;
    else tremor = 0;
    if (highlight > 0) highlight -= 0.02;
  }

  void display() {
    float ox = (tremor > 0) ? random(-tremor, tremor) : 0;
    float oy = (tremor > 0) ? random(-tremor, tremor) : 0;
    float dx = x + ox, dy = y + oy;
    color c = quakeColor(value);

    noStroke();
    fill(red(c), green(c), blue(c), 40);
    ellipse(dx, dy, radius*4, radius*4);
    fill(c);
    ellipse(dx, dy, radius*2, radius*2);

    // ホバーでツールチップ
    if (dist(mouseX, mouseY, x, y) < radius + 8) {
      String tip = "M" + nf(mag, 1, 1) + " " + place;
      fill(0, 200);
      noStroke();
      rect(mouseX + 10, mouseY - 28, textWidth(tip) + 16, 24, 4);
      fill(255);
      textAlign(LEFT, CENTER);
      textSize(12);
      text(tip, mouseX + 18, mouseY - 16);
    }

    // ハイライト
    if (highlight > 0) {
      noFill();
      stroke(255, highlight * 200);
      strokeWeight(1);
      ellipse(dx, dy, radius*3, radius*3);
    }
  }

  boolean isHovered(float mx, float my) {
    return dist(mx, my, x, y) < radius + 8;
  }
}

// ============================================================
class Ripple {
  float x, y;
  int value;
  color c;
  float maxRadius, currentRadius, speed, life, strokeW, delay;

  Ripple(float x, float y, int value, color c, float delay) {
    this.x=x;
    this.y=y;
    this.value=value;
    this.c=c;
    this.delay=delay;
    maxRadius=map(value, 1, 8, 60, 280);
    speed=map(value, 1, 8, 1.2, 3.5);
    strokeW=map(value, 1, 8, 1.5, 5);
    currentRadius=0;
    life=1;
  }

  void update() {
    if (delay>0) {
      delay--;
      return;
    }
    currentRadius+=speed;
    life=1-(currentRadius/maxRadius);
  }

  void display() {
    if (delay>0||life<=0)return;
    noFill();
    float a=life*life*255;
    for (int i=3; i>=1; i--) {
      stroke(red(c), green(c), blue(c), a*0.3/i);
      strokeWeight(strokeW*life+i*2);
      ellipse(x, y, currentRadius*2, currentRadius*2);
    }
    stroke(red(c), green(c), blue(c), a);
    strokeWeight(strokeW*life);
    ellipse(x, y, currentRadius*2, currentRadius*2);
    if (value>=5) {
      float d=map(value, 5, 8, 2, 6)*life;
      stroke(red(c), green(c), blue(c), a*0.5);
      strokeWeight(strokeW*life*0.5);
      ellipse(x, y, currentRadius*2+random(-d, d), currentRadius*2+random(-d, d));
    }
  }

  boolean isDead() {
    return delay<=0&&life<=0;
  }
}

// ============================================================
class Crack {
  float x, y;
  int value;
  color c;
  float maxLen, currentLen, speed, life, angle;
  ArrayList<PVector> points;

  Crack(float x, float y, int value, color c) {
    this.x=x;
    this.y=y;
    this.value=value;
    this.c=c;
    angle=random(TWO_PI);
    maxLen=map(value, 4, 8, 30, 140);
    currentLen=0;
    speed=map(value, 4, 8, 2, 5);
    life=1;
    points=new ArrayList<PVector>();
    points.add(new PVector(x, y));
    float cx=x, cy=y, seg=7;
    int n=(int)(maxLen/seg);
    for (int i=0; i<n; i++) {
      float j=random(-0.4, 0.4);
      cx+=cos(angle+j)*seg;
      cy+=sin(angle+j)*seg;
      points.add(new PVector(cx, cy));
      if (random(1)<0.3)angle+=random(-0.5, 0.5);
    }
  }

  void update() {
    if (currentLen<maxLen)currentLen+=speed;
    else life-=0.015;
  }

  void display() {
    if (life<=0)return;
    float p=currentLen/maxLen;
    int dc=min((int)(p*points.size()), points.size()-1);
    stroke(red(c), green(c), blue(c), life*60);
    strokeWeight(map(value, 4, 8, 3, 8)*life);
    noFill();
    beginShape();
    for (int i=0; i<=dc; i++)vertex(points.get(i).x, points.get(i).y);
    endShape();
    stroke(255, life*220);
    strokeWeight(map(value, 4, 8, 1, 2.5)*life);
    beginShape();
    for (int i=0; i<=dc; i++)vertex(points.get(i).x, points.get(i).y);
    endShape();
  }

  boolean isDead() {
    return life<=0;
  }
}

// ============================================================
class Particle {
  float x, y, vx, vy, life, decay, sz;
  color c;

  Particle(float x, float y, int value, color c) {
    this.x=x;
    this.y=y;
    this.c=c;
    float a=random(TWO_PI), s=random(1, map(value, 1, 8, 3, 8));
    vx=cos(a)*s;
    vy=sin(a)*s;
    life=1;
    decay=random(0.01, 0.03);
    sz=random(map(value, 1, 8, 1, 2), map(value, 1, 8, 3, 7));
  }

  void update() {
    x+=vx;
    y+=vy;
    vx*=0.96;
    vy*=0.96;
    vy+=0.04;
    life-=decay;
  }

  void display() {
    if (life<=0)return;
    noStroke();
    float a=life*255;
    fill(255, a*0.8);
    ellipse(x, y, sz*0.5, sz*0.5);
    fill(red(c), green(c), blue(c), a*0.6);
    ellipse(x, y, sz, sz);
  }

  boolean isDead() {
    return life<=0;
  }
}

// ============================================================
class Flash {
  float x, y, life, maxSize;
  int value;
  color c;

  Flash(float x, float y, int value, color c) {
    this.x=x;
    this.y=y;
    this.value=value;
    this.c=c;
    life=1;
    maxSize=map(value, 3, 8, 50, 200);
  }

  void update() {
    life-=map(value, 3, 8, 0.06, 0.03);
  }

  void display() {
    if (life<=0)return;
    noStroke();
    float s=maxSize*(1-life*0.5);
    for (int i=5; i>=1; i--) {
      float t=i/5.0;
      fill(red(c), green(c), blue(c), life*life*80*t);
      ellipse(x, y, s*t, s*t);
    }
    fill(255, life*life*150);
    ellipse(x, y, s*0.15, s*0.15);
  }

  boolean isDead() {
    return life<=0;
  }
}

