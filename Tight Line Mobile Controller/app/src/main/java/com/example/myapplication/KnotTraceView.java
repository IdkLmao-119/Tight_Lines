package com.example.myapplication;

import android.content.Context;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.DashPathEffect;
import android.graphics.Paint;
import android.graphics.Path;
import android.graphics.RectF;
import android.util.AttributeSet;
import android.view.MotionEvent;
import android.view.View;

import java.util.ArrayList;
import java.util.List;
import java.util.Random;

/**
 * Interactive touchscreen tracing view for the Tight Lines mobile knotting minigame.
 * Renders a fishing knot guide path and tracks sequential finger tracing so self-crossing
 * knot loops cannot be shortcutted.
 */
public class KnotTraceView extends View {

    public interface OnKnotListener {
        void onProgress(float progress);
        void onFailedAttempt(String reason);
        void onKnotCompleted(String knotName, float accuracy);
    }

    private static class KnotPattern {
        final String name;
        final float[][] controlPoints; // normalized [0..1] x [0..1]

        KnotPattern(String name, float[][] controlPoints) {
            this.name = name;
            this.controlPoints = controlPoints;
        }
    }

    // Classic fishing knot single-stroke patterns (normalized coordinates in [0.12..0.88])
    private static final KnotPattern[] PATTERNS = new KnotPattern[] {
        new KnotPattern("Figure-Eight Knot", new float[][] {
            {0.16f, 0.82f},
            {0.24f, 0.62f},
            {0.50f, 0.48f},
            {0.76f, 0.34f},
            {0.74f, 0.16f},
            {0.50f, 0.13f},
            {0.26f, 0.18f},
            {0.28f, 0.36f},
            {0.50f, 0.50f},
            {0.74f, 0.64f},
            {0.72f, 0.83f},
            {0.50f, 0.86f},
            {0.34f, 0.78f},
            {0.56f, 0.58f},
            {0.84f, 0.50f}
        }),
        new KnotPattern("Overhand Loop", new float[][] {
            {0.14f, 0.68f},
            {0.34f, 0.64f},
            {0.62f, 0.58f},
            {0.78f, 0.42f},
            {0.72f, 0.20f},
            {0.48f, 0.14f},
            {0.24f, 0.24f},
            {0.22f, 0.46f},
            {0.40f, 0.66f},
            {0.66f, 0.76f},
            {0.86f, 0.68f}
        }),
        new KnotPattern("Clinch Twist", new float[][] {
            {0.16f, 0.78f},
            {0.22f, 0.46f},
            {0.36f, 0.18f},
            {0.54f, 0.22f},
            {0.46f, 0.50f},
            {0.36f, 0.76f},
            {0.56f, 0.82f},
            {0.72f, 0.62f},
            {0.68f, 0.34f},
            {0.84f, 0.22f}
        })
    };

    private static final int SAMPLE_POINTS = 84;
    private static final int LOOKAHEAD_STEPS = 12;
    private static final int LOOKBACK_STEPS = 5;
    private static final long PROGRESS_SEND_INTERVAL_MS = 85L;
    private static final long ERROR_FLASH_DURATION_MS = 380L;

    private final Random random = new Random();
    private KnotPattern activePattern;
    private float[] normX = new float[0];
    private float[] normY = new float[0];
    private float[] screenX = new float[0];
    private float[] screenY = new float[0];

    private final Path guidePath = new Path();
    private final Path tracedPath = new Path();
    private final Path chevronPath = new Path();
    private final RectF boardRect = new RectF();

    private final Paint boardFillPaint = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Paint boardRimOuterPaint = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Paint boardRimInnerPaint = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Paint corridorPaint = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Paint guideRopePaint = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Paint chevronPaint = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Paint tracedGlowPaint = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Paint tracedRopePaint = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Paint startFillPaint = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Paint startPulsePaint = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Paint endRingPaint = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Paint endCorePaint = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Paint beadGlowPaint = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Paint beadCorePaint = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Paint labelPaint = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Paint errorFlashPaint = new Paint(Paint.ANTI_ALIAS_FLAG);

    private OnKnotListener listener;
    private int currentIndex = 0;
    private boolean isTracing = false;
    private boolean isCompleted = false;
    private float tolerancePx = 64f;
    private float accumulatedErrorRatio = 0f;
    private int accuracySamples = 0;

    private long lastProgressSentMs = 0L;
    private long errorFlashUntilMs = 0L;
    private float pulsePhase = 0f;

    private final Runnable pulseTicker = new Runnable() {
        @Override
        public void run() {
            pulsePhase = (pulsePhase + 0.14f) % (float) (Math.PI * 2.0);
            invalidate();
            if (isAttachedToWindow()) {
                postDelayed(this, 32L);
            }
        }
    };

    public KnotTraceView(Context context) {
        super(context);
        init();
    }

    public KnotTraceView(Context context, AttributeSet attrs) {
        super(context, attrs);
        init();
    }

    public KnotTraceView(Context context, AttributeSet attrs, int defStyleAttr) {
        super(context, attrs, defStyleAttr);
        init();
    }

    private void init() {
        boardFillPaint.setColor(Color.parseColor("#CC0A264E"));
        boardFillPaint.setStyle(Paint.Style.FILL);

        boardRimOuterPaint.setColor(Color.parseColor("#3B2312"));
        boardRimOuterPaint.setStyle(Paint.Style.STROKE);
        boardRimOuterPaint.setStrokeWidth(14f);

        boardRimInnerPaint.setColor(Color.parseColor("#C89B6E"));
        boardRimInnerPaint.setStyle(Paint.Style.STROKE);
        boardRimInnerPaint.setStrokeWidth(4f);

        corridorPaint.setColor(Color.parseColor("#2A7EC8FF"));
        corridorPaint.setStyle(Paint.Style.STROKE);
        corridorPaint.setStrokeCap(Paint.Cap.ROUND);
        corridorPaint.setStrokeJoin(Paint.Join.ROUND);

        guideRopePaint.setColor(Color.parseColor("#99CFE6FF"));
        guideRopePaint.setStyle(Paint.Style.STROKE);
        guideRopePaint.setStrokeWidth(12f);
        guideRopePaint.setStrokeCap(Paint.Cap.ROUND);
        guideRopePaint.setStrokeJoin(Paint.Join.ROUND);
        guideRopePaint.setPathEffect(new DashPathEffect(new float[]{22f, 16f}, 0f));

        chevronPaint.setColor(Color.parseColor("#CCF4C95D"));
        chevronPaint.setStyle(Paint.Style.STROKE);
        chevronPaint.setStrokeWidth(5f);
        chevronPaint.setStrokeCap(Paint.Cap.ROUND);
        chevronPaint.setStrokeJoin(Paint.Join.ROUND);

        tracedGlowPaint.setColor(Color.parseColor("#77F4C95D"));
        tracedGlowPaint.setStyle(Paint.Style.STROKE);
        tracedGlowPaint.setStrokeWidth(28f);
        tracedGlowPaint.setStrokeCap(Paint.Cap.ROUND);
        tracedGlowPaint.setStrokeJoin(Paint.Join.ROUND);

        tracedRopePaint.setColor(Color.parseColor("#FFF3DC"));
        tracedRopePaint.setStyle(Paint.Style.STROKE);
        tracedRopePaint.setStrokeWidth(13f);
        tracedRopePaint.setStrokeCap(Paint.Cap.ROUND);
        tracedRopePaint.setStrokeJoin(Paint.Join.ROUND);

        startFillPaint.setColor(Color.parseColor("#2A9D8F"));
        startFillPaint.setStyle(Paint.Style.FILL);

        startPulsePaint.setColor(Color.parseColor("#662A9D8F"));
        startPulsePaint.setStyle(Paint.Style.FILL);

        endRingPaint.setColor(Color.parseColor("#F4C95D"));
        endRingPaint.setStyle(Paint.Style.STROKE);
        endRingPaint.setStrokeWidth(7f);

        endCorePaint.setColor(Color.parseColor("#E07A5F"));
        endCorePaint.setStyle(Paint.Style.FILL);

        beadGlowPaint.setColor(Color.parseColor("#88F4C95D"));
        beadGlowPaint.setStyle(Paint.Style.FILL);

        beadCorePaint.setColor(Color.parseColor("#FFF9EE"));
        beadCorePaint.setStyle(Paint.Style.FILL);

        labelPaint.setColor(Color.parseColor("#FFF9EE"));
        labelPaint.setTextSize(26f);
        labelPaint.setTextAlign(Paint.Align.CENTER);
        labelPaint.setFakeBoldText(true);

        errorFlashPaint.setColor(Color.parseColor("#55FF4B3E"));
        errorFlashPaint.setStyle(Paint.Style.FILL);

        pickRandomKnot();
    }

    @Override
    protected void onAttachedToWindow() {
        super.onAttachedToWindow();
        removeCallbacks(pulseTicker);
        post(pulseTicker);
    }

    @Override
    protected void onDetachedFromWindow() {
        super.onDetachedFromWindow();
        removeCallbacks(pulseTicker);
    }

    public void setOnKnotListener(OnKnotListener listener) {
        this.listener = listener;
    }

    public String getKnotName() {
        return activePattern != null ? activePattern.name : "Fishing Knot";
    }

    public void pickRandomKnot() {
        activePattern = PATTERNS[random.nextInt(PATTERNS.length)];
        buildNormalizedSamples(activePattern.controlPoints);
        resetTraceState();
        rebuildScreenGeometry(getWidth(), getHeight());
        invalidate();
    }

    public void resetTraceState() {
        currentIndex = 0;
        isTracing = false;
        isCompleted = false;
        accumulatedErrorRatio = 0f;
        accuracySamples = 0;
        tracedGlowPaint.setColor(Color.parseColor("#77F4C95D"));
        tracedRopePaint.setColor(Color.parseColor("#FFF3DC"));
        rebuildTracedPath();
        invalidate();
    }

    private void buildNormalizedSamples(float[][] ctrl) {
        if (ctrl == null || ctrl.length < 2) {
            normX = new float[0];
            normY = new float[0];
            return;
        }
        // First build dense Catmull-Rom curve points
        List<float[]> dense = new ArrayList<>();
        int segCount = ctrl.length - 1;
        int stepsPerSeg = 14;
        for (int i = 0; i < segCount; i++) {
            float[] p0 = ctrl[Math.max(0, i - 1)];
            float[] p1 = ctrl[i];
            float[] p2 = ctrl[i + 1];
            float[] p3 = ctrl[Math.min(ctrl.length - 1, i + 2)];

            for (int s = 0; s < stepsPerSeg; s++) {
                float t = (float) s / (float) stepsPerSeg;
                float x = catmullRom(p0[0], p1[0], p2[0], p3[0], t);
                float y = catmullRom(p0[1], p1[1], p2[1], p3[1], t);
                dense.add(new float[]{x, y});
            }
        }
        dense.add(new float[]{ctrl[ctrl.length - 1][0], ctrl[ctrl.length - 1][1]});

        // Compute arc length and resample uniformly into SAMPLE_POINTS
        int m = dense.size();
        float[] cumLen = new float[m];
        cumLen[0] = 0f;
        for (int i = 1; i < m; i++) {
            float dx = dense.get(i)[0] - dense.get(i - 1)[0];
            float dy = dense.get(i)[1] - dense.get(i - 1)[1];
            cumLen[i] = cumLen[i - 1] + (float) Math.hypot(dx, dy);
        }
        float totalLen = Math.max(cumLen[m - 1], 0.0001f);

        normX = new float[SAMPLE_POINTS];
        normY = new float[SAMPLE_POINTS];
        int cursor = 0;
        for (int i = 0; i < SAMPLE_POINTS; i++) {
            float target = (totalLen * i) / (float) (SAMPLE_POINTS - 1);
            while (cursor < m - 2 && cumLen[cursor + 1] < target) {
                cursor++;
            }
            float segLen = Math.max(cumLen[cursor + 1] - cumLen[cursor], 0.00001f);
            float localT = Math.max(0f, Math.min(1f, (target - cumLen[cursor]) / segLen));
            float[] a = dense.get(cursor);
            float[] b = dense.get(cursor + 1);
            normX[i] = a[0] + (b[0] - a[0]) * localT;
            normY[i] = a[1] + (b[1] - a[1]) * localT;
        }
    }

    private static float catmullRom(float p0, float p1, float p2, float p3, float t) {
        float t2 = t * t;
        float t3 = t2 * t;
        return 0.5f * ((2f * p1)
                + (-p0 + p2) * t
                + (2f * p0 - 5f * p1 + 4f * p2 - p3) * t2
                + (-p0 + 3f * p1 - 3f * p2 + p3) * t3);
    }

    @Override
    protected void onSizeChanged(int w, int h, int oldw, int oldh) {
        super.onSizeChanged(w, h, oldw, oldh);
        rebuildScreenGeometry(w, h);
    }

    private void rebuildScreenGeometry(int w, int h) {
        if (w <= 0 || h <= 0 || normX.length == 0) return;

        float pad = 12f;
        boardRect.set(pad, pad, w - pad, h - pad);

        float innerW = Math.max(1f, boardRect.width() - 32f);
        float innerH = Math.max(1f, boardRect.height() - 32f);
        float drawSize = Math.min(innerW, innerH);
        float left = boardRect.centerX() - drawSize / 2f;
        float top = boardRect.centerY() - drawSize / 2f;

        tolerancePx = Math.max(46f, drawSize * 0.135f);
        corridorPaint.setStrokeWidth(tolerancePx * 1.15f);

        screenX = new float[normX.length];
        screenY = new float[normY.length];
        guidePath.reset();
        for (int i = 0; i < normX.length; i++) {
            screenX[i] = left + normX[i] * drawSize;
            screenY[i] = top + normY[i] * drawSize;
            if (i == 0) {
                guidePath.moveTo(screenX[i], screenY[i]);
            } else {
                guidePath.lineTo(screenX[i], screenY[i]);
            }
        }
        rebuildTracedPath();
    }

    private void rebuildTracedPath() {
        tracedPath.reset();
        if (screenX.length == 0 || currentIndex <= 0) return;
        int limit = Math.min(currentIndex, screenX.length - 1);
        tracedPath.moveTo(screenX[0], screenY[0]);
        for (int i = 1; i <= limit; i++) {
            tracedPath.lineTo(screenX[i], screenY[i]);
        }
    }

    @Override
    protected void onDraw(Canvas canvas) {
        super.onDraw(canvas);
        if (screenX.length == 0) return;

        // Board background & wooden border
        canvas.drawRoundRect(boardRect, 34f, 34f, boardFillPaint);
        canvas.drawRoundRect(boardRect, 34f, 34f, boardRimOuterPaint);
        canvas.drawRoundRect(boardRect, 30f, 30f, boardRimInnerPaint);

        // Brief red error tint on off-path failure
        long now = System.currentTimeMillis();
        if (now < errorFlashUntilMs) {
            float alphaFrac = (float) (errorFlashUntilMs - now) / (float) ERROR_FLASH_DURATION_MS;
            errorFlashPaint.setAlpha(Math.round(115f * alphaFrac));
            canvas.drawRoundRect(boardRect, 30f, 30f, errorFlashPaint);
        }

        // Soft tolerance corridor + dashed guide rope
        canvas.drawPath(guidePath, corridorPaint);
        canvas.drawPath(guidePath, guideRopePaint);

        // Directional chevrons along the remaining untraced path
        drawDirectionChevrons(canvas);

        // Traced golden-cream rope
        if (currentIndex > 0) {
            canvas.drawPath(tracedPath, tracedGlowPaint);
            canvas.drawPath(tracedPath, tracedRopePaint);
        }

        // End target eyelet
        int last = screenX.length - 1;
        float ex = screenX[last];
        float ey = screenY[last];
        float endPulse = 1f + 0.12f * (float) Math.sin(pulsePhase);
        canvas.drawCircle(ex, ey, 24f * endPulse, endRingPaint);
        canvas.drawCircle(ex, ey, 11f, endCorePaint);
        canvas.drawText("END", ex, ey - 32f, labelPaint);

        // Start anchor node
        float sx = screenX[0];
        float sy = screenY[0];
        if (!isTracing && !isCompleted) {
            float startPulse = 1f + 0.28f * (0.5f + 0.5f * (float) Math.sin(pulsePhase * 1.4f));
            canvas.drawCircle(sx, sy, 32f * startPulse, startPulsePaint);
        }
        canvas.drawCircle(sx, sy, 23f, startFillPaint);
        canvas.drawCircle(sx, sy, 23f, endRingPaint);
        if (!isTracing && !isCompleted) {
            canvas.drawText("START", sx, sy - 34f, labelPaint);
        }

        // Active glowing bead at current trace front
        if (isTracing || isCompleted) {
            int idx = Math.min(currentIndex, last);
            float bx = screenX[idx];
            float by = screenY[idx];
            float beadScale = isCompleted ? (1.25f + 0.15f * (float) Math.sin(pulsePhase * 2f)) : 1f;
            canvas.drawCircle(bx, by, 28f * beadScale, beadGlowPaint);
            canvas.drawCircle(bx, by, 14f * beadScale, beadCorePaint);
        }
    }

    private void drawDirectionChevrons(Canvas canvas) {
        int n = screenX.length;
        int startIdx = Math.max(4, currentIndex + 4);
        float size = 12f;
        for (int i = startIdx; i < n - 3; i += 10) {
            float dx = screenX[i + 1] - screenX[i - 1];
            float dy = screenY[i + 1] - screenY[i - 1];
            float len = (float) Math.hypot(dx, dy);
            if (len < 0.001f) continue;
            float ux = dx / len;
            float uy = dy / len;
            // Perpendicular vector
            float px = -uy;
            float py = ux;

            float tipX = screenX[i] + ux * (size * 0.5f);
            float tipY = screenY[i] + uy * (size * 0.5f);
            float leftX = screenX[i] - ux * (size * 0.6f) + px * (size * 0.7f);
            float leftY = screenY[i] - uy * (size * 0.6f) + py * (size * 0.7f);
            float rightX = screenX[i] - ux * (size * 0.6f) - px * (size * 0.7f);
            float rightY = screenY[i] - uy * (size * 0.6f) - py * (size * 0.7f);

            chevronPath.reset();
            chevronPath.moveTo(leftX, leftY);
            chevronPath.lineTo(tipX, tipY);
            chevronPath.lineTo(rightX, rightY);
            canvas.drawPath(chevronPath, chevronPaint);
        }
    }

    @Override
    public boolean onTouchEvent(MotionEvent event) {
        if (isCompleted || screenX.length == 0) {
            return true;
        }

        float tx = event.getX();
        float ty = event.getY();

        switch (event.getActionMasked()) {
            case MotionEvent.ACTION_DOWN: {
                float distToStart = (float) Math.hypot(tx - screenX[0], ty - screenY[0]);
                if (distToStart <= tolerancePx * 1.35f) {
                    isTracing = true;
                    currentIndex = 0;
                    accumulatedErrorRatio = 0f;
                    accuracySamples = 0;
                    rebuildTracedPath();
                    if (getParent() != null) {
                        getParent().requestDisallowInterceptTouchEvent(true);
                    }
                    notifyProgress(0f, true);
                    invalidate();
                } else {
                    triggerErrorFlash();
                    if (listener != null) {
                        listener.onFailedAttempt("start_missed");
                    }
                }
                return true;
            }

            case MotionEvent.ACTION_MOVE: {
                if (!isTracing) return true;

                int last = screenX.length - 1;
                int bestFwdIdx = currentIndex;
                float bestFwdDist = Float.MAX_VALUE;
                int maxIdx = Math.min(last, currentIndex + LOOKAHEAD_STEPS);
                for (int i = currentIndex; i <= maxIdx; i++) {
                    float d = (float) Math.hypot(tx - screenX[i], ty - screenY[i]);
                    if (d < bestFwdDist) {
                        bestFwdDist = d;
                        bestFwdIdx = i;
                    }
                }

                // Also check a tiny lookback window so jittering in place doesn't falsely fail
                float bestBackDist = bestFwdDist;
                int minIdx = Math.max(0, currentIndex - LOOKBACK_STEPS);
                for (int i = minIdx; i < currentIndex; i++) {
                    float d = (float) Math.hypot(tx - screenX[i], ty - screenY[i]);
                    if (d < bestBackDist) {
                        bestBackDist = d;
                    }
                }

                float nearestDist = Math.min(bestFwdDist, bestBackDist);
                if (nearestDist > tolerancePx) {
                    failAndReset("off_path");
                    return true;
                }

                if (bestFwdIdx > currentIndex) {
                    currentIndex = bestFwdIdx;
                    accumulatedErrorRatio += Math.min(1f, bestFwdDist / Math.max(tolerancePx, 1f));
                    accuracySamples++;
                    rebuildTracedPath();

                    float progress = (float) currentIndex / (float) last;
                    notifyProgress(progress, false);

                    // Snap to completion if at or right beside the END node
                    float distToEnd = (float) Math.hypot(tx - screenX[last], ty - screenY[last]);
                    if (currentIndex >= last - 1 || (currentIndex >= last - 5 && distToEnd <= tolerancePx * 0.85f)) {
                        completeKnot();
                    }
                }
                invalidate();
                return true;
            }

            case MotionEvent.ACTION_UP:
            case MotionEvent.ACTION_CANCEL: {
                if (isTracing && !isCompleted) {
                    failAndReset("lifted");
                }
                return true;
            }
        }
        return super.onTouchEvent(event);
    }

    private void failAndReset(String reason) {
        isTracing = false;
        currentIndex = 0;
        accumulatedErrorRatio = 0f;
        accuracySamples = 0;
        rebuildTracedPath();
        triggerErrorFlash();
        notifyProgress(0f, true);
        if (listener != null) {
            listener.onFailedAttempt(reason);
        }
        invalidate();
    }

    private void completeKnot() {
        isTracing = false;
        isCompleted = true;
        currentIndex = screenX.length - 1;
        rebuildTracedPath();

        // Celebratory teal-gold cinch glow
        tracedGlowPaint.setColor(Color.parseColor("#AA2A9D8F"));
        tracedRopePaint.setColor(Color.parseColor("#F4C95D"));

        float avgError = accuracySamples > 0 ? (accumulatedErrorRatio / (float) accuracySamples) : 0f;
        float accuracy = Math.max(0.5f, Math.min(1.0f, 1.0f - avgError * 0.5f));

        notifyProgress(1.0f, true);
        invalidate();

        if (listener != null) {
            listener.onKnotCompleted(getKnotName(), accuracy);
        }
    }

    private void triggerErrorFlash() {
        errorFlashUntilMs = System.currentTimeMillis() + ERROR_FLASH_DURATION_MS;
        invalidate();
    }

    private void notifyProgress(float progress, boolean force) {
        if (listener == null) return;
        long now = System.currentTimeMillis();
        if (force || now - lastProgressSentMs >= PROGRESS_SEND_INTERVAL_MS) {
            lastProgressSentMs = now;
            listener.onProgress(Math.max(0f, Math.min(1f, progress)));
        }
    }
}
