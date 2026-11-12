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

    private final Paint ringPaint = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Paint spokePaint = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Paint handlePaint = new Paint(Paint.ANTI_ALIAS_FLAG);

    private float currentAngleDeg = 0f;
    private float lastTouchAngleDeg = 0f;
    private boolean isDragging = false;

    // Accumulate small movements to avoid flooding the WebSocket
    private float accumulatedDelta = 0f;
    private long lastSendTimeMs = 0L;
    private static final long SEND_INTERVAL_MS = 50L;

    public FishingReelView(Context context, AttributeSet attrs) {
        super(context, attrs);
        init();
    }

    private void init() {
        ringPaint.setColor(Color.parseColor("#64FFDA"));
        ringPaint.setStyle(Paint.Style.STROKE);
        ringPaint.setStrokeWidth(16f);

        spokePaint.setColor(Color.parseColor("#3A4F7A"));
        spokePaint.setStyle(Paint.Style.STROKE);
        spokePaint.setStrokeWidth(8f);

        handlePaint.setColor(Color.parseColor("#E94560"));
        handlePaint.setStyle(Paint.Style.FILL);
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

        // Outer reel circle
        canvas.drawCircle(cx, cy, radius, ringPaint);

        // Cross spokes so rotation is visually obvious
        canvas.drawLine(cx - radius, cy, cx + radius, cy, spokePaint);
        canvas.drawLine(cx, cy - radius, cx, cy + radius, spokePaint);

        // Reel handle/knob near the edge
        canvas.drawCircle(cx + radius * 0.75f, cy, 28f, handlePaint);

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
                lastTouchAngleDeg = touchAngleDeg;
                // Prevent parent views from intercepting the drag
                getParent().requestDisallowInterceptTouchEvent(true);
                return true;

            case MotionEvent.ACTION_MOVE:
                if (!isDragging) return false;

                float delta = touchAngleDeg - lastTouchAngleDeg;
                // Normalize delta to [-180, 180] to handle wrap-around
                if (delta > 180f) delta -= 360f;
                if (delta < -180f) delta += 360f;

                currentAngleDeg = (currentAngleDeg + delta) % 360f;
                lastTouchAngleDeg = touchAngleDeg;
                invalidate();

                accumulatedDelta += delta;
                long now = System.currentTimeMillis();
                if (listener != null && now - lastSendTimeMs >= SEND_INTERVAL_MS && Math.abs(accumulatedDelta) > 1f) {
                    listener.onReel(accumulatedDelta);
                    accumulatedDelta = 0f;
                    lastSendTimeMs = now;
                }
                return true;

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