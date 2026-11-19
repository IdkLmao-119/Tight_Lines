package com.example.myapplication;

import android.content.Context;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Paint;
import android.util.AttributeSet;
import android.view.MotionEvent;
import android.view.View;

public class FishingReelView extends View {

    public interface OnReelListener {
        void onReel(float deltaDegrees);
    }

    private OnReelListener listener;

    private final Paint shadowBorderPaint = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Paint spoolCorePaint = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Paint lineWindPaint = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Paint ringPaint = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Paint goldRimPaint = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Paint spokePaint = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Paint hubCapPaint = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Paint handleHaloPaint = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Paint handlePaint = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Paint handleRimPaint = new Paint(Paint.ANTI_ALIAS_FLAG);

    private float currentAngleDeg = 0f;
    private float lastTouchAngleDeg = 0f;
    private boolean isDragging = false;

    // Accumulate small movements to avoid flooding the WebSocket
    private float accumulatedDelta = 0f;
    private long lastSendTimeMs = 0L;
    private static final long SEND_INTERVAL_MS = 50L;
    private static final float MIN_RADIUS_FRACTION = 0.25f; // ignore touches this close to the center
    private static final float MAX_STEP_DEG = 60f;          // one MOVE event can't rotate more than this
    public FishingReelView(Context context, AttributeSet attrs) {
        super(context, attrs);
        init();
    }

    private void init() {
        shadowBorderPaint.setColor(Color.parseColor("#3B2312"));
        shadowBorderPaint.setStyle(Paint.Style.STROKE);
        shadowBorderPaint.setStrokeWidth(26f);

        spoolCorePaint.setColor(Color.parseColor("#103763"));
        spoolCorePaint.setStyle(Paint.Style.FILL);

        lineWindPaint.setColor(Color.parseColor("#2A5E9E"));
        lineWindPaint.setStyle(Paint.Style.STROKE);
        lineWindPaint.setStrokeWidth(4f);

        ringPaint.setColor(Color.parseColor("#D4A259"));
        ringPaint.setStyle(Paint.Style.STROKE);
        ringPaint.setStrokeWidth(18f);

        goldRimPaint.setColor(Color.parseColor("#F4C95D"));
        goldRimPaint.setStyle(Paint.Style.STROKE);
        goldRimPaint.setStrokeWidth(4f);

        spokePaint.setColor(Color.parseColor("#D4A259"));
        spokePaint.setStyle(Paint.Style.STROKE);
        spokePaint.setStrokeWidth(11f);
        spokePaint.setStrokeCap(Paint.Cap.ROUND);

        hubCapPaint.setColor(Color.parseColor("#F4C95D"));
        hubCapPaint.setStyle(Paint.Style.FILL);

        handleHaloPaint.setColor(Color.parseColor("#66F4C95D"));
        handleHaloPaint.setStyle(Paint.Style.FILL);

        handlePaint.setColor(Color.parseColor("#7A4E2D"));
        handlePaint.setStyle(Paint.Style.FILL);

        handleRimPaint.setColor(Color.parseColor("#FFF3DC"));
        handleRimPaint.setStyle(Paint.Style.STROKE);
        handleRimPaint.setStrokeWidth(4f);
    }

    public void setOnReelListener(OnReelListener listener) {
        this.listener = listener;
    }

    @Override
    protected void onDraw(Canvas canvas) {
        super.onDraw(canvas);

        float cx = getWidth() / 2f;
        float cy = getHeight() / 2f;
        float radius = Math.min(cx, cy) - 40f;

        canvas.save();
        canvas.rotate(currentAngleDeg, cx, cy);

        // Deep-ocean spool core & wound fishing line rings
        canvas.drawCircle(cx, cy, radius, spoolCorePaint);
        canvas.drawCircle(cx, cy, radius * 0.76f, lineWindPaint);
        canvas.drawCircle(cx, cy, radius * 0.56f, lineWindPaint);
        canvas.drawCircle(cx, cy, radius * 0.36f, lineWindPaint);

        // Brushed brass reel rim with dark outline & gold highlight
        canvas.drawCircle(cx, cy, radius, shadowBorderPaint);
        canvas.drawCircle(cx, cy, radius, ringPaint);
        canvas.drawCircle(cx, cy, radius + 5f, goldRimPaint);

        // Bold brass spokes
        canvas.drawLine(cx - radius * 0.9f, cy, cx + radius * 0.9f, cy, spokePaint);
        canvas.drawLine(cx, cy - radius * 0.9f, cx, cy + radius * 0.9f, spokePaint);

        // Center brass cap + bolt
        canvas.drawCircle(cx, cy, 24f, hubCapPaint);
        canvas.drawCircle(cx, cy, 10f, handlePaint);

        // Wooden crank handle/knob near the edge
        float hx = cx + radius * 0.75f;
        if (isDragging) {
            canvas.drawCircle(hx, cy, 42f, handleHaloPaint);
        }
        canvas.drawCircle(hx, cy, 28f, handlePaint);
        canvas.drawCircle(hx, cy, 28f, handleRimPaint);

        canvas.restore();
    }

    @Override
    public boolean onTouchEvent(MotionEvent event) {
        float cx = getWidth() / 2f;
        float cy = getHeight() / 2f;
        float dx = event.getX() - cx;
        float dy = event.getY() - cy;

        float touchAngleDeg = (float) Math.toDegrees(Math.atan2(dy, dx));

        switch (event.getActionMasked()) {
            case MotionEvent.ACTION_DOWN:
                isDragging = true;
                accumulatedDelta = 0f;               // NEW: no leftovers from the last crank
                lastTouchAngleDeg = touchAngleDeg;
                getParent().requestDisallowInterceptTouchEvent(true);
                return true;

            case MotionEvent.ACTION_MOVE: {
                if (!isDragging) return false;

                float ringRadius = Math.min(cx, cy) - 40f;
                float touchRadius = (float) Math.hypot(dx, dy);

                float delta = touchAngleDeg - lastTouchAngleDeg;
                if (delta > 180f) delta -= 360f;
                if (delta < -180f) delta += 360f;
                lastTouchAngleDeg = touchAngleDeg;

                // Too close to the center, or an impossible jump: the angle is meaningless.
                if (touchRadius < ringRadius * MIN_RADIUS_FRACTION || Math.abs(delta) > MAX_STEP_DEG) {
                    return true;
                }

                currentAngleDeg = (currentAngleDeg + delta) % 360f;
                invalidate();

                long now = System.currentTimeMillis();

                // Flush previous direction's movement if user reverses direction mid-drag
                if ((accumulatedDelta > 0f && delta < 0f) || (accumulatedDelta < 0f && delta > 0f)) {
                    if (listener != null && Math.abs(accumulatedDelta) > 1f) {
                        listener.onReel(accumulatedDelta);
                        lastSendTimeMs = now;
                    }
                    accumulatedDelta = 0f;
                }

                accumulatedDelta += delta;
                if (listener != null && now - lastSendTimeMs >= SEND_INTERVAL_MS
                        && Math.abs(accumulatedDelta) > 1f) {
                    listener.onReel(accumulatedDelta);
                    accumulatedDelta = 0f;
                    lastSendTimeMs = now;
                }
                return true;
            }
            case MotionEvent.ACTION_UP:
            case MotionEvent.ACTION_CANCEL:
                isDragging = false;
                if (listener != null && Math.abs(accumulatedDelta) > 1f) {
                    listener.onReel(accumulatedDelta);
                    accumulatedDelta = 0f;
                }
                return true;
        }
        return super.onTouchEvent(event);
    }
}