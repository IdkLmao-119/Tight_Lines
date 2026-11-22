package com.example.myapplication;

import android.content.Context;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Paint;
import android.graphics.Path;
import android.os.Handler;
import android.os.Looper;
import android.util.AttributeSet;
import android.view.MotionEvent;
import android.view.View;

public class DPadView extends View {

    public interface OnMoveListener {
        void onMove(float x, float y);
    }

    private OnMoveListener listener;

    private final Paint borderPaint = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Paint woodRingPaint = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Paint bevelPaint = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Paint basePaint = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Paint activeHaloPaint = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Paint activePaint = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Paint arrowPaint = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Paint activeArrowPaint = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Paint centerCapPaint = new Paint(Paint.ANTI_ALIAS_FLAG);

    private float currentX = 0f;
    private float currentY = 0f;
    private boolean isPressed = false;

    private final Handler handler = new Handler(Looper.getMainLooper());
    private static final long STREAM_INTERVAL_MS = 50L;

    private final Runnable streamRunnable = new Runnable() {
        @Override
        public void run() {
            if (isPressed && listener != null) {
                listener.onMove(currentX, currentY);
                handler.postDelayed(this, STREAM_INTERVAL_MS);
            }
        }
    };

    public DPadView(Context context, AttributeSet attrs) {
        super(context, attrs);
        init();
    }

    private void init() {
        borderPaint.setColor(Color.parseColor("#3B2312"));
        borderPaint.setStyle(Paint.Style.FILL);

        woodRingPaint.setColor(Color.parseColor("#6C4527"));
        woodRingPaint.setStyle(Paint.Style.FILL);

        bevelPaint.setColor(Color.parseColor("#C89B6E"));
        bevelPaint.setStyle(Paint.Style.STROKE);
        bevelPaint.setStrokeWidth(4f);

        basePaint.setColor(Color.parseColor("#123A6F"));
        basePaint.setStyle(Paint.Style.FILL);

        activeHaloPaint.setColor(Color.parseColor("#55F4C95D"));
        activeHaloPaint.setStyle(Paint.Style.FILL);

        activePaint.setColor(Color.parseColor("#E6F4C95D"));
        activePaint.setStyle(Paint.Style.FILL);

        arrowPaint.setColor(Color.parseColor("#FFF3DC"));
        arrowPaint.setStyle(Paint.Style.FILL);

        activeArrowPaint.setColor(Color.parseColor("#FFE28A"));
        activeArrowPaint.setStyle(Paint.Style.FILL);

        centerCapPaint.setColor(Color.parseColor("#7A4E2D"));
        centerCapPaint.setStyle(Paint.Style.FILL);
    }

    public void setOnMoveListener(OnMoveListener listener) {
        this.listener = listener;
    }

    @Override
    protected void onDetachedFromWindow() {
        super.onDetachedFromWindow();
        isPressed = false;
        currentX = 0f;
        currentY = 0f;
        handler.removeCallbacks(streamRunnable);
        removeCallbacks(streamRunnable);
        if (listener != null) {
            listener.onMove(0f, 0f);
        }
    }

    @Override
    protected void onDraw(Canvas canvas) {
        super.onDraw(canvas);

        float cx = getWidth() / 2f;
        float cy = getHeight() / 2f;
        float radius = Math.min(cx, cy) - 10f;

        // Cozy wooden outer frame + inner deep-ocean disc
        canvas.drawCircle(cx, cy, radius, borderPaint);
        canvas.drawCircle(cx, cy, radius * 0.94f, woodRingPaint);
        canvas.drawCircle(cx, cy, radius * 0.84f, bevelPaint);
        canvas.drawCircle(cx, cy, radius * 0.82f, basePaint);

        // Warm golden active direction glow
        boolean moving = isPressed && (currentX != 0f || currentY != 0f);
        if (moving) {
            float ax = cx + currentX * radius * 0.42f;
            float ay = cy + currentY * radius * 0.42f;
            canvas.drawCircle(ax, ay, radius * 0.38f, activeHaloPaint);
            canvas.drawCircle(ax, ay, radius * 0.25f, activePaint);
        }

        // Draw directional arrows
        float arrowSize = radius * 0.18f;
        drawArrow(canvas, cx, cy - radius * 0.56f, arrowSize, 0, moving && currentY < 0f);   // UP
        drawArrow(canvas, cx + radius * 0.56f, cy, arrowSize, 90, moving && currentX > 0f);  // RIGHT
        drawArrow(canvas, cx, cy + radius * 0.56f, arrowSize, 180, moving && currentY > 0f); // DOWN
        drawArrow(canvas, cx - radius * 0.56f, cy, arrowSize, 270, moving && currentX < 0f); // LEFT

        // Subtle center wooden cap
        canvas.drawCircle(cx, cy, radius * 0.14f, borderPaint);
        canvas.drawCircle(cx, cy, radius * 0.10f, centerCapPaint);
    }

    private void drawArrow(Canvas canvas, float cx, float cy, float size, float angleDeg, boolean active) {
        canvas.save();
        canvas.rotate(angleDeg, cx, cy);

        Path path = new Path();
        path.moveTo(cx, cy - size);
        path.lineTo(cx - size * 0.7f, cy + size * 0.5f);
        path.lineTo(cx + size * 0.7f, cy + size * 0.5f);
        path.close();

        canvas.drawPath(path, active ? activeArrowPaint : arrowPaint);
        canvas.restore();
    }

    @Override
    public boolean onTouchEvent(MotionEvent event) {
        float cx = getWidth() / 2f;
        float cy = getHeight() / 2f;
        float dx = event.getX() - cx;
        float dy = event.getY() - cy;

        switch (event.getActionMasked()) {
            case MotionEvent.ACTION_DOWN:
            case MotionEvent.ACTION_MOVE: {
                isPressed = true;
                if (getParent() != null) {
                    getParent().requestDisallowInterceptTouchEvent(true);
                }

                float radius = Math.min(cx, cy);
                float normX = dx / radius;
                float normY = dy / radius;

                // Deadzone check
                float mag = (float) Math.hypot(normX, normY);
                if (mag < 0.15f) {
                    currentX = 0f;
                    currentY = 0f;
                } else {
                    // Strict 4-way cardinal direction (no diagonal movement)
                    if (Math.abs(dx) >= Math.abs(dy)) {
                        currentX = dx > 0 ? 1.0f : -1.0f;
                        currentY = 0.0f;
                    } else {
                        currentX = 0.0f;
                        currentY = dy > 0 ? 1.0f : -1.0f;
                    }
                }

                invalidate();

                if (listener != null) {
                    listener.onMove(currentX, currentY);
                }

                handler.removeCallbacks(streamRunnable);
                handler.postDelayed(streamRunnable, STREAM_INTERVAL_MS);
                return true;
            }

            case MotionEvent.ACTION_UP:
            case MotionEvent.ACTION_CANCEL: {
                isPressed = false;
                currentX = 0f;
                currentY = 0f;
                invalidate();

                handler.removeCallbacks(streamRunnable);
                if (listener != null) {
                    listener.onMove(0f, 0f);
                }
                return true;
            }
        }
        return super.onTouchEvent(event);
    }
}
